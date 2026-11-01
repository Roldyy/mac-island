// SPDX-License-Identifier: GPL-3.0-or-later
// Lane W3A (switcher). The lane owns this file.

import AppKit
import SwiftUI

/// The ported window switcher (the ⌘Tab replacement), bound through `PortFeatureBinding`.
///
/// One feature, `switcher`, with the Settings page `switcher` (page 28). The registry decides whether it runs
/// (off by default, kill switch, safe mode, crash quarantine, a revoked Accessibility grant), and
/// `PortFeatureBinding` never starts it without Accessibility and never prompts. Screen Recording is NOT a start
/// gate (the catalog lists Accessibility only, patch 0700): without it the cards show the app icon instead of a
/// thumbnail and the page says so.
///
/// Start is `AppSwitcher.syncWithPreferences()` behind the availability probe: a macOS that dropped the symbol
/// the window mapping needs leaves the switcher off and ⌘Tab with macOS. Stop is `AppSwitcher.suspend()`, which
/// gives the native ⌘Tab back (`SystemShortcutTakeover` source `switcher`) and removes the tap.
///
/// Giving ⌘Tab back, on every path:
/// - stop (switch off, kill switch, safe mode, quarantine, permission revoke): `suspend()` -> `restoreNativeHotkeys()`;
/// - quit: `willTerminate` -> `quit` below (`suspend()` when started, then `SystemShortcutTakeover.restoreAll()`);
/// - the tap cannot be created, the system disables it, secure input, wake: handled inside `AppSwitcher`;
/// - a crash or a kill: `SystemShortcutTakeover` writes its marker (`systemShortcutsSuppressed`) BEFORE it flips a
///   key, and `PortBridge.recoverAtLaunch` calls `SystemShortcutTakeover.recoverIfNeeded` when the marker is set.
enum SwitcherLane {
    static let upstreamID = "switcher"
    static let pageID = "switcher"

    /// What the lane does to the ported services. Tests pass fakes: the live one arms a real event tap.
    struct Runtime {
        var start: @MainActor () -> Void
        var stop: @MainActor () -> Void
        /// The app is quitting; `wasStarted` is whether the registry had started the switcher.
        var quit: @MainActor (_ wasStarted: Bool) -> Void

        static let live = Runtime(
            start: { SwitcherLane.start(probe: SwitcherProbe.live, sync: { AppSwitcher.shared.syncWithPreferences() }) },
            stop: { AppSwitcher.shared.suspend() },
            quit: { wasStarted in
                if wasStarted { AppSwitcher.shared.suspend() }
                // Every key any feature took over goes back, whichever feature held it (nobody else does this).
                SystemShortcutTakeover.restoreAll()
            })
    }

    /// What `PortFeatureBinding` runs once permissions and the registry allow it: the probe first, so a macOS
    /// that cannot map windows never gets an armed tap in front of the keyboard.
    @MainActor
    static func start(probe: SwitcherProbeReport, sync: () -> Void) {
        guard !probe.blocksStart else { return }
        sync()
    }

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live)
        guard !didInstallLaunchSafety else { return }
        didInstallLaunchSafety = true
        observeTermination(of: binding, runtime: .live)
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: Runtime) {
        binding.bind(.switcher,
                     page: PortFeaturePage(pageID: pageID) { AnyView(SwitcherSettings()) },
                     start: runtime.start, stop: runtime.stop)
    }

    private nonisolated(unsafe) static var didInstallLaunchSafety = false

    /// The app delegate does not know the switcher, so the lane gives ⌘Tab back itself when the app quits
    /// normally. No queue: the notification is posted on the main thread and the restore must finish before the
    /// process goes. A crash or a kill is covered by the launch recovery instead.
    @MainActor @discardableResult
    static func observeTermination(of binding: PortFeatureBinding, runtime: Runtime,
                                   center: NotificationCenter = .default) -> NSObjectProtocol {
        center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated {
                runtime.quit(binding.isStarted(PortFeatureIDs.registryID(forUpstream: upstreamID)))
            }
        }
    }
}

// MARK: - Takeover consent

/// Hiding macOS's own ⌘Tab needs a yes given in THIS app. Vorssaint's `switcherTakeOverSystemShortcuts` is
/// migrated like any preference, but a choice made in another app is not consent here (the same rule as
/// `SystemShortcutTakeover.consentKey`): the toggle, on the page, writes this key, and the takeover needs both.
enum SwitcherTakeoverConsent {
    static let key = "switcherTakeOverConsent.macisland"

    static func isGranted(_ defaults: UserDefaults) -> Bool { defaults.bool(forKey: key) }

    static func set(_ on: Bool, defaults: UserDefaults) {
        if on { defaults.set(true, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    static func isEffective(toggle: Bool, defaults: UserDefaults) -> Bool {
        toggle && isGranted(defaults)
    }

    static let pendingNote =
        "Ce réglage a été repris de l'ancienne app : ⌘Tab de macOS reste actif tant que vous ne l'avez pas réactivé ici."
}

// MARK: - Stuck overlay

/// Rules that close a switcher session nobody is driving.
enum SwitcherSessionSafety {
    /// Seconds without a key, a click, a scroll or a selection change before the overlay closes by itself.
    static let idleTimeout: TimeInterval = 30

    /// Another app became frontmost while the session was open (a click elsewhere, Mission Control, a dialog):
    /// the session is over. The app that was in front when it opened is not a change.
    static func shouldCancelOnActivation(activatedPID: pid_t?, sessionFrontPID: pid_t?) -> Bool {
        guard let activatedPID else { return false }
        return activatedPID != sessionFrontPID
    }
}

/// One timer that fires `onExpire` after `timeout` unless it is re-armed or disarmed first. Main thread only (the
/// session state it protects is too). The scheduler is a seam so a test advances time by hand.
final class SwitcherSessionWatchdog {
    /// Schedules `work` after `delay` seconds and returns what cancels it.
    typealias Schedule = (_ delay: TimeInterval, _ work: @escaping () -> Void) -> () -> Void

    private let timeout: TimeInterval
    private let schedule: Schedule
    private var cancelPending: (() -> Void)?

    init(timeout: TimeInterval = SwitcherSessionSafety.idleTimeout, schedule: @escaping Schedule = liveSchedule) {
        self.timeout = timeout
        self.schedule = schedule
    }

    var isArmed: Bool { cancelPending != nil }

    /// Starts (or restarts) the countdown.
    func arm(onExpire: @escaping () -> Void) {
        cancelPending?()
        cancelPending = schedule(timeout) { [weak self] in
            self?.cancelPending = nil
            onExpire()
        }
    }

    func disarm() {
        cancelPending?()
        cancelPending = nil
    }

    static let liveSchedule: Schedule = { delay, work in
        let item = DispatchWorkItem(block: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return { item.cancel() }
    }
}

// MARK: - Private-API probe

/// What the switcher needs from the window server, probed by symbol name and never called: each private
/// capability that is missing on this macOS is named here with a French reason, and only the one the whole switcher
/// stands on blocks the start. Everything else degrades (the ported code already answers nil for a missing symbol).
struct SwitcherProbeReport: Equatable {
    struct Finding: Equatable {
        let capability: SwitcherProbe.Capability
        let reason: String
    }

    let findings: [Finding]

    var blocksStart: Bool { findings.contains { $0.capability.blocksStart } }
    var blockingReason: String? { findings.first { $0.capability.blocksStart }?.reason }
    var degraded: [Finding] { findings.filter { !$0.capability.blocksStart } }
}

enum SwitcherProbe {
    enum Capability: CaseIterable {
        /// Accessibility window -> window server id. Without it no window can be named: the switcher stays off.
        case windowIdentity
        /// Windows parked on other desktops and fullscreen Spaces.
        case otherSpaces
        /// Window thumbnails.
        case thumbnails
        /// Precise raise of a window on another desktop.
        case activation
        /// Switching macOS's own ⌘Tab off.
        case nativeShortcutTakeover

        var blocksStart: Bool { self == .windowIdentity }

        var symbols: [String] {
            switch self {
            case .windowIdentity:
                return ["_AXUIElementGetWindow"]
            case .otherSpaces:
                return ["CGSMainConnectionID", "CGSCopyManagedDisplaySpaces", "CGSCopySpacesForWindows",
                        "CGSGetWindowTags", "CGSWindowIsOrderedIn", "CGSMoveWindowsToManagedSpace",
                        "SLSWindowQueryWindows", "SLSWindowQueryResultCopyWindows", "SLSWindowIteratorAdvance",
                        "SLSWindowIteratorGetWindowID", "SLSWindowIteratorGetTags"]
            case .thumbnails:
                return ["CGSMainConnectionID", "CGSHWCaptureWindowList"]
            case .activation:
                return ["_SLPSSetFrontProcessWithOptions", "SLPSPostEventRecordTo"]
            case .nativeShortcutTakeover:
                return ["CGSSetSymbolicHotKeyEnabled", "CGSIsSymbolicHotKeyEnabled", "CGSGetSymbolicHotKeyValue"]
            }
        }

        var reason: String {
            switch self {
            case .windowIdentity:
                return "Ce macOS n'expose plus le lien entre fenêtre et Accessibilité : le sélecteur reste éteint et ⌘Tab reste celui de macOS."
            case .otherSpaces:
                return "Les fenêtres des autres bureaux ne sont plus listées sur ce macOS."
            case .thumbnails:
                return "Les aperçus de fenêtres ne sont pas disponibles sur ce macOS : le sélecteur montre les icônes."
            case .activation:
                return "La mise au premier plan précise d'une fenêtre n'est pas disponible sur ce macOS : le sélecteur utilise l'activation standard."
            case .nativeShortcutTakeover:
                return "Mac Island ne peut pas désactiver ⌘Tab de macOS ici : choisissez un autre raccourci pour le sélecteur."
            }
        }
    }

    /// The report for a symbol table. A capability is missing when ANY of its symbols is.
    static func evaluate(isPresent: (String) -> Bool) -> SwitcherProbeReport {
        SwitcherProbeReport(findings: Capability.allCases.compactMap { capability in
            capability.symbols.allSatisfy(isPresent) ? nil : SwitcherProbeReport.Finding(
                capability: capability, reason: capability.reason)
        })
    }

    /// The real symbol table, read once (a lookup, never a call). The lookups live in `SpaceWindowBridge`, a file
    /// the private-API allowlist already lists.
    static let live: SwitcherProbeReport = evaluate(isPresent: SpaceWindowBridge.isSymbolAvailable)

    static let screenRecordingNote =
        "Sans l'enregistrement de l'écran, le sélecteur affiche l'icône de chaque application à la place de l'aperçu de ses fenêtres. Il fonctionne quand même."
}

/// The page's line about what this macOS cannot do. Nothing when everything is there.
struct SwitcherProbeNotice: View {
    var body: some View {
        let findings = SwitcherProbe.live.findings
        if !findings.isEmpty {
            SettingsCard(title: "Disponibilité sur ce macOS") {
                ForEach(findings.indices, id: \.self) { index in
                    Text(findings[index].reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
