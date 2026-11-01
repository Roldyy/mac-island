// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management

import Foundation
import IslandKit
import SwiftUI

/// One Settings page body a ported feature brings: our page id (`SettingsPageCatalog`) and the ported view.
public struct PortFeaturePage {
    public let pageID: String
    public let body: @MainActor () -> AnyView

    public init(pageID: String, body: @escaping @MainActor () -> AnyView) {
        self.pageID = pageID
        self.body = body
    }
}

/// The one way a lane turns a ported Vorssaint feature on, safely.
///
/// A lane calls `bind` once, from its `Bridge/<Lane>.swift`, with the upstream feature id and two closures:
/// `start` (the upstream service's start, usually `Service.shared.syncWithPreferences()`) and `stop` (its
/// stop). Binding creates the `FeatureDescriptor` (French title and summary, permissions and risk, all read
/// from the ported `FeatureCatalog`), so the feature gets a switch in the Features page, a status, the
/// kill switch, safe mode and crash quarantine from `FeatureRegistry`, and wraps the two closures so that:
///
/// - the feature is OFF unless the registry says on (the descriptor is off by default, so only a migrated
///   or user-chosen `shell.enabled.<id>` turns it on);
/// - `start` never runs while a permission the feature uses (Accessibility, Screen Recording) is missing, and
///   nothing here ever prompts: the registry restarts the feature when the monitor sees the grant;
/// - `start` is idempotent, `stop` always reaches the upstream stop (the upstream stops are idempotent), and both
///   run on the main actor;
/// - `AppFeature.isAvailable` answers with the registry's verdict for the feature, so a toggle on a ported page
///   cannot restart a service the registry stopped (kill switch, safe mode, quarantine, off).
///
/// Binding adds no starter by itself: the app delegate passes `descriptors`, `starters` and `stoppers` to the
/// registry before `launch`, and `pages` to `SettingsPageBodies`.
@MainActor
public final class PortFeatureBinding {
    /// The app's binding. Lanes bind into it from `PortLanes`.
    public static let shared = PortFeatureBinding()

    private struct Entry {
        let descriptor: FeatureDescriptor
        let permissions: Set<Gate>
        let start: @MainActor () -> Void
        let stop: @MainActor () -> Void
        let page: PortFeaturePage?
        /// False for a feature that REPLACES one of our modules (`bindReplacing`): the registry already holds our
        /// descriptor for that id, so the binding adds none and gates nothing by it.
        let ownsDescriptor: Bool
    }

    /// The permissions of the system that `PortPermissionState` can answer.
    private enum Gate: Hashable { case accessibility, screenRecording }

    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private var started: Set<String> = []
    private let state = LockedState()
    private let permissions: @Sendable () -> PortPermissionState

    /// `permissions` reads the latest permission state; tests pass a fake.
    public init(permissions: @escaping @Sendable () -> PortPermissionState = { PortHost.permissionState.value }) {
        self.permissions = permissions
    }

    // MARK: Binding

    /// Binds one ported feature by its upstream id (`AppFeature` raw value). Returns its descriptor, or nil
    /// when the id is unknown, already bound, or owned by one of our own modules (`PortFeatureIDs`).
    @discardableResult
    public func bind(_ upstreamID: String, page: PortFeaturePage? = nil,
                     start: @escaping @MainActor () -> Void,
                     stop: @escaping @MainActor () -> Void) -> FeatureDescriptor? {
        guard let feature = AppFeature(rawValue: upstreamID) else { return nil }
        return bind(feature, page: page, start: start, stop: stop)
    }

    @discardableResult
    func bind(_ feature: AppFeature, page: PortFeaturePage? = nil,
              start: @escaping @MainActor () -> Void,
              stop: @escaping @MainActor () -> Void) -> FeatureDescriptor? {
        let id = feature.registryID
        guard !PortFeatureIDs.isOwnedByExistingModule(feature.rawValue), entries[id] == nil else { return nil }
        let descriptor = Self.descriptor(for: feature)
        entries[id] = Entry(descriptor: descriptor, permissions: Self.gates(of: descriptor),
                            start: start, stop: stop, page: page, ownsDescriptor: true)
        order.append(id)
        state.bind(id)
        return descriptor
    }

    /// Binds a ported feature that REPLACES one of our own modules (`PortFeatureIDs.existing`: `mixer` replaces
    /// the `audio` module). The registry keeps OUR descriptor (title, switch, island tab, migrated
    /// `shell.enabled.<id>`), so no descriptor is added and no permission gate is built from the catalog; the
    /// ported services re-check what they need themselves. Everything else is `bind`: registry start and stop,
    /// idempotence, the availability hook and the page. False when the id is not an existing module's, unknown,
    /// or already bound. The caller removes the old module's starter and stopper in the same change.
    @discardableResult
    public func bindReplacing(_ upstreamID: String, page: PortFeaturePage? = nil,
                              start: @escaping @MainActor () -> Void,
                              stop: @escaping @MainActor () -> Void) -> Bool {
        guard let feature = AppFeature(rawValue: upstreamID),
              PortFeatureIDs.isOwnedByExistingModule(feature.rawValue), entries[feature.registryID] == nil else {
            return false
        }
        let id = feature.registryID
        entries[id] = Entry(descriptor: Self.descriptor(for: feature), permissions: [], start: start, stop: stop,
                            page: page, ownsDescriptor: false)
        order.append(id)
        state.bind(id)
        return true
    }

    /// Descriptors to append to the registry's, in binding order.
    public var descriptors: [FeatureDescriptor] {
        order.compactMap { entries[$0].flatMap { $0.ownsDescriptor ? $0.descriptor : nil } }
    }

    /// Registry id -> starter. Pass to `FeatureRegistry.launch`.
    public var starters: [String: @MainActor () -> Void] {
        Dictionary(uniqueKeysWithValues: order.map { id in (id, { [unowned self] in self.runStart(id) }) })
    }

    /// Registry id -> stopper. Pass to `FeatureRegistry.launch`.
    public var stoppers: [String: @MainActor () -> Void] {
        Dictionary(uniqueKeysWithValues: order.map { id in (id, { [unowned self] in self.runStop(id) }) })
    }

    /// The pages to hand to `SettingsPageBodies`: (page id, registry feature id, body). The body already
    /// reads the host's defaults for `@AppStorage`.
    public var pages: [(pageID: String, featureID: String, body: @MainActor () -> AnyView)] {
        order.compactMap { id in
            guard let page = entries[id]?.page else { return nil }
            return (page.pageID, id, { AnyView(page.body().defaultAppStorage(PortHost.defaults)) })
        }
    }

    // MARK: Start and stop

    private func runStart(_ id: String) {
        guard let entry = entries[id] else { return }
        state.allow(id)
        guard !started.contains(id) else { return }
        guard permissionsGranted(entry) else { return }  // never arm, never prompt: the monitor restarts us
        started.insert(id)
        entry.start()
    }

    private func runStop(_ id: String) {
        guard let entry = entries[id] else { return }
        state.deny(id)
        started.remove(id)
        entry.stop()
    }

    private func permissionsGranted(_ entry: Entry) -> Bool {
        guard !entry.permissions.isEmpty else { return true }
        let now = permissions()
        return entry.permissions.allSatisfy { gate in
            switch gate {
            case .accessibility: now.accessibility
            case .screenRecording: now.screenRecording
            }
        }
    }

    /// True once the registry started the feature and until it stopped it, whatever the permissions say.
    public func isStarted(_ registryID: String) -> Bool { state.isAllowed(registryID) }

    // MARK: Host hook

    /// What `AppFeature.isAvailable` reads: nil for a feature nobody bound, the registry's verdict for a bound
    /// one. Safe from any thread.
    public nonisolated func availability(_ registryID: String) -> Bool? { state.availability(registryID) }

    /// Plugs `availability` into the ported code. The app delegate calls it once, before `launch`.
    public func connectAvailability() {
        let state = state
        PortHost.availability = { state.availability($0) }
    }

    // MARK: Descriptor

    /// The descriptor of a ported feature: French text from the ported hub strings, permissions and risk from
    /// the catalog, never on by default.
    static func descriptor(for feature: AppFeature) -> FeatureDescriptor {
        let l10n = L10n.shared
        let hub = FeatureStrings.hub(l10n.language)
        return FeatureDescriptor(
            id: feature.registryID,
            title: feature.hubTitle(l10n.s, hub: hub),
            summary: feature.hubDescription(hub),
            systemImage: feature.symbolName,
            category: category(of: feature.group),
            permissions: featurePermissions(of: feature),
            risk: risk(of: feature),
            enabledByDefault: false,
            tabID: nil)
    }

    static func category(of group: FeatureGroup) -> FeatureCategory {
        switch group {
        case .windowsDock: .windows
        case .mouseKeyboard: .input
        case .clipboardFiles: .files
        case .sound: .sound
        case .energyDisplay: .display
        case .tools: .tools
        case .dynamicIsland: .island
        case .monitor: .monitor
        }
    }

    /// `AppFeature.permissions` (what the feature can use) in the shell's vocabulary. Files and Folders and App
    /// Management have no shell counterpart and are left out.
    static func featurePermissions(of feature: AppFeature) -> [FeaturePermission] {
        var result: [FeaturePermission] = []
        for permission in feature.permissions {
            let mapped: FeaturePermission?
            switch permission {
            case .accessibility: mapped = .accessibility
            case .screenRecording: mapped = .screenRecording
            case .fullDiskAccess: mapped = .fullDiskAccess
            case .notifications: mapped = .notifications
            case .automationFinder, .automationTerminal, .automationPlayback: mapped = .automation
            case .audioCapture: mapped = .audioCapture
            case .microphone: mapped = .microphone
            case .camera: mapped = .camera
            case .calendar: mapped = .calendar
            case .filesAndFolders, .appManagement: mapped = nil
            }
            if let mapped, !result.contains(mapped) { result.append(mapped) }
        }
        return result
    }

    /// `privileged`: needs the root helper. `touchesSystem`: changes a system setting or another app's data.
    /// `touchesInput`: reads or rewrites input events (the Accessibility features). Everything else is safe.
    static func risk(of feature: AppFeature) -> FeatureRisk {
        switch feature {
        case .fanControl:
            return .privileged
        case .mouseAcceleration, .superKey, .spacesOrder, .bluetoothSleep, .extraBrightness, .brightness, .micMute,
             .killProcess, .cleaner, .uninstaller, .diskImageInstaller, .homebrew, .wallpaper, .keepAwake,
             .soundOutputSwitcher, .audioPriority, .mixer, .quickToggles, .appUpdates:
            return .touchesSystem
        default:
            return feature.permissions.contains(.accessibility) ? .touchesInput : .safe
        }
    }

    private static func gates(of descriptor: FeatureDescriptor) -> Set<Gate> {
        var gates: Set<Gate> = []
        for permission in descriptor.permissions {
            switch permission {
            case .accessibility: gates.insert(.accessibility)
            case .screenRecording: gates.insert(.screenRecording)
            default: break
            }
        }
        return gates
    }
}

/// The ids a binding owns and the ids the registry let run, readable from any thread: the ported services
/// ask `isAvailable` from event-tap callbacks and background queues.
private final class LockedState: @unchecked Sendable {
    private let lock = NSLock()
    private var bound: Set<String> = []
    private var allowed: Set<String> = []

    func bind(_ id: String) { lock.lock(); bound.insert(id); lock.unlock() }
    func allow(_ id: String) { lock.lock(); allowed.insert(id); lock.unlock() }
    func deny(_ id: String) { lock.lock(); allowed.remove(id); lock.unlock() }
    func isAllowed(_ id: String) -> Bool { lock.lock(); defer { lock.unlock() }; return allowed.contains(id) }
    func availability(_ id: String) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return bound.contains(id) ? allowed.contains(id) : nil
    }
}
