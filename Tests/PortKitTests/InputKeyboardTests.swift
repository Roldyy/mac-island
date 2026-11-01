import AppKit
import Foundation
import IslandKit
import IslandTestSupport
import SwiftUI
import Testing
@testable import PortKit
@testable import ShellKit

/// Lane W1-C: the four keyboard features bound through `PortFeatureBinding`, driven by a real `FeatureRegistry`,
/// a fake runtime (the live one arms real event taps) and a fake permission state. Nothing here creates a tap,
/// runs `hidutil` or asks for a permission.
@MainActor
@Suite(.serialized) struct InputKeyboardTests {
    static let ids = ["quitWindowProtection", "keyboardDebounce", "superKey", "textSnippets"]

    final class Log {
        var events: [String] = []
        func count(_ event: String) -> Int { events.filter { $0 == event }.count }
    }

    struct Rig {
        let binding: PortFeatureBinding
        let registry: FeatureRegistry
        let log: Log
        let permissions: Box<PortPermissionState>
        let cleanup: () -> Void
    }

    func fakeRuntime(_ log: Log) -> InputKeyboardLane.Runtime {
        func hooks(_ name: String) -> InputKeyboardLane.Runtime.Hooks {
            .init(start: { log.events.append("start \(name)") }, stop: { log.events.append("stop \(name)") })
        }
        return .init(quitProtection: hooks("quitWindowProtection"), keyboardDebounce: hooks("keyboardDebounce"),
                     superKey: hooks("superKey"), textSnippets: hooks("textSnippets"))
    }

    func rig(granted: Bool = true, switchedOn: Bool = true) -> Rig {
        let permissions = Box(PortPermissionState(accessibility: granted))
        let binding = PortFeatureBinding(permissions: { permissions.value })
        let log = Log()
        InputKeyboardLane.bind(into: binding, runtime: fakeRuntime(log))
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let probe = PermissionProbe(accessibility: { permissions.value.accessibility },
                                    screenRecording: { false }, inputMonitoring: { false }, automation: { _ in nil })
        let registry = FeatureRegistry(descriptors: binding.descriptors, defaults: bench.defaults, crashMarker: marker,
                                       capabilityProvider: SystemCapabilities.provider(probe), withdraw: { _ in })
        if switchedOn { for d in binding.descriptors { registry.switches[d.id] = true } }
        binding.connectAvailability()
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        return Rig(binding: binding, registry: registry, log: log, permissions: permissions,
                   cleanup: { bench.cleanup(); marker.clear() })
    }

    /// Runs `body` against a rig inside the host fixture: `connectAvailability` is process-wide state.
    func withRig(granted: Bool = true, switchedOn: Bool = true, _ body: @MainActor (Rig) -> Void) {
        PortHostFixture.isolated { _ in
            let r = rig(granted: granted, switchedOn: switchedOn)
            defer { r.cleanup() }
            body(r)
        }
    }

    func change(_ rig: Rig, to new: PortPermissionState) {
        let old = rig.permissions.value
        rig.permissions.value = new
        rig.registry.permissionsChanged(PermissionChange(
            old: PermissionSnapshot(accessibility: old.accessibility, inputMonitoring: old.inputMonitoring,
                                    screenRecording: old.screenRecording),
            new: PermissionSnapshot(accessibility: new.accessibility, inputMonitoring: new.inputMonitoring,
                                    screenRecording: new.screenRecording)))
    }

    // MARK: Descriptors and pages

    @Test func theLaneBindsTheFourFeaturesWithTheirDescriptors() {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        InputKeyboardLane.bind(into: binding, runtime: fakeRuntime(Log()))
        #expect(binding.descriptors.map(\.id) == Self.ids)
        for d in binding.descriptors {
            #expect(d.category == .input && d.permissions == [.accessibility], "\(d.id)")
            #expect(!d.enabledByDefault, "\(d.id) is never on by default")
            #expect(!d.title.isEmpty && !d.summary.isEmpty)
        }
        let risks = Dictionary(uniqueKeysWithValues: binding.descriptors.map { ($0.id, $0.risk) })
        #expect(risks["superKey"] == .touchesSystem, "it rewrites the keyboard mapping through hidutil")
        #expect(risks["keyboardDebounce"] == .touchesInput && risks["quitWindowProtection"] == .touchesInput
            && risks["textSnippets"] == .touchesInput)
        #expect(binding.pages.map(\.pageID) == ["quitprotect", "debounce", "superkey", "snippets"])
        #expect(binding.pages.map(\.featureID) == Self.ids)
        for page in binding.pages { #expect(SettingsPageCatalog.page(page.pageID) != nil, "\(page.pageID)") }
    }

    @Test func theLiveLaneBindsTheSameFour() {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        InputKeyboardLane.bind(into: binding, runtime: .live)
        #expect(binding.descriptors.map(\.id) == Self.ids)
    }

    @Test func theFourPagesGetARealBodyAndStopBeingComingSoon() {
        SettingsPageBodies.removeAll()
        defer { SettingsPageBodies.removeAll() }
        withRig { r in
            for id in ["quitprotect", "debounce", "superkey", "snippets"] {
                #expect(SettingsPageCatalog.page(id)?.isComingSoon == true, "\(id): the catalog row alone is a stub")
            }
            for ported in r.binding.pages {
                SettingsPageBodies.register(pageID: ported.pageID, featureID: ported.featureID, registry: r.registry,
                                            openPermission: { _ in }, ported.body)
            }
            for id in ["quitprotect", "debounce", "superkey", "snippets"] {
                let page = SettingsPageCatalog.page(id)!
                #expect(!page.isComingSoon && SettingsPageBodies.hasBody(for: id), "\(id)")
                let host = NSHostingView(rootView: SettingsPageScaffold(page: page) { EmptyView() })
                host.frame = NSRect(x: 0, y: 0, width: 760, height: 1000)
                host.layoutSubtreeIfNeeded()
                #expect(host.fittingSize.height > 250, "\(id) rendered \(host.fittingSize)")
            }
        }
    }

    // MARK: Registry: start, stop, kill switch, safe mode, permissions

    @Test func nothingStartsUntilTheRegistrySaysOn() {
        withRig(switchedOn: false) { r in
            #expect(r.log.events.isEmpty)
            for id in Self.ids { #expect(r.registry.state(for: id) == .off, "\(id)") }
            for feature in [AppFeature.keyboardDebounce, .superKey, .quitWindowProtection, .textSnippets] {
                #expect(!feature.isAvailable, "\(feature.rawValue): off means the ported code reads off")
            }
        }
    }

    @Test func eachFeatureStartsAndStopsWithItsOwnSwitch() {
        withRig(switchedOn: false) { r in
            for id in Self.ids {
                r.registry.switches[id] = true
                #expect(r.log.count("start \(id)") == 1, "\(id) start")
                r.registry.switches[id] = false
                #expect(r.log.count("stop \(id)") == 1, "\(id) stop")
            }
        }
    }

    @Test func theKillSwitchStopsAllFourAndTheyComeBackWhenItIsReleased() {
        withRig { r in
            for id in Self.ids { #expect(r.log.count("start \(id)") == 1) }
            r.registry.killSwitch = true
            for id in Self.ids {
                #expect(r.log.count("stop \(id)") == 1, "\(id) stopped by the kill switch")
                #expect(r.registry.state(for: id) == .killed)
            }
            for feature in [AppFeature.keyboardDebounce, .superKey, .quitWindowProtection, .textSnippets] {
                #expect(!feature.isAvailable, "\(feature.rawValue): the ported taps read off, so they pass every key through")
            }
            r.registry.killSwitch = false
            for id in Self.ids { #expect(r.log.count("start \(id)") == 2, "\(id) restarted") }
        }
    }

    @Test func safeModeStopsAllFour() {
        withRig { r in
            r.registry.safeMode = true
            for id in Self.ids { #expect(r.log.count("stop \(id)") == 1, "\(id)") }
        }
    }

    @Test func withoutAccessibilityNothingStartsAndNothingPrompts() {
        withRig(granted: false) { r in
            #expect(r.log.events.isEmpty, "the permission gate keeps start from running")
            change(r, to: PortPermissionState(accessibility: true))
            for id in Self.ids { #expect(r.log.count("start \(id)") == 1, "\(id) starts on the grant") }
        }
    }

    @Test func aRevokedAccessibilityStopsAllFourAndAGrantRestartsThem() {
        withRig { r in
            change(r, to: PortPermissionState(accessibility: false))
            for id in Self.ids { #expect(r.log.count("stop \(id)") == 1, "\(id) stopped on revoke") }
            change(r, to: PortPermissionState(accessibility: true))
            for id in Self.ids { #expect(r.log.count("start \(id)") == 2, "\(id) restarted on grant") }
        }
    }

    @Test func startIsIdempotentAndStopAlwaysReachesTheService() {
        withRig { r in
            for _ in 0..<3 { r.binding.starters["superKey"]?() }
            #expect(r.log.count("start superKey") == 1)
            r.binding.stoppers["superKey"]?()
            r.binding.stoppers["superKey"]?()
            #expect(r.log.count("stop superKey") == 2, "stop is always forwarded: the upstream stops are idempotent")
        }
    }

    // MARK: Live services, safe to touch with every page toggle off

    @Test func theLiveStopsAreHarmlessWhenNothingRuns() {
        PortHostFixture.isolated { defaults in
            #expect(!defaults.bool(forKey: DefaultsKey.superKeyMappingApplied))
            let live = InputKeyboardLane.Runtime.live
            for hooks in [live.quitProtection, live.keyboardDebounce, live.superKey, live.textSnippets] {
                hooks.stop()
                hooks.stop()
            }
            #expect(!QuitProtectionService.shared.isRunning)
            #expect(!KeyboardDebounceService.shared.isRunning)
            #expect(!SuperKeyService.shared.isRunning)
            #expect(!TextSnippetService.shared.isRunning)
        }
    }

    @Test func theLiveStartsArmNothingWhileTheirPageTogglesAreOff() {
        PortHostFixture.isolated { defaults in
            #expect(!defaults.bool(forKey: DefaultsKey.keyboardDebounceEnabled))
            let live = InputKeyboardLane.Runtime.live
            for hooks in [live.quitProtection, live.keyboardDebounce, live.superKey, live.textSnippets] { hooks.start() }
            #expect(!QuitProtectionService.shared.isRunning)
            #expect(!KeyboardDebounceService.shared.isRunning)
            #expect(!SuperKeyService.shared.isRunning)
            #expect(!TextSnippetService.shared.isRunning)
            for hooks in [live.quitProtection, live.keyboardDebounce, live.superKey, live.textSnippets] { hooks.stop() }
        }
    }

    // MARK: Launch and quit safety of the super key

    @Test func aLeftoverMappingMarkerIsClearedBeforeTheRegistryStarts() {
        PortHostFixture.isolated { defaults in
            var cleared = 0
            #expect(!InputKeyboardLane.recoverLeftoverMapping(defaults: defaults) { cleared += 1 })
            #expect(cleared == 0, "no marker, no hidutil")
            defaults.set(true, forKey: DefaultsKey.superKeyMappingApplied)
            #expect(InputKeyboardLane.recoverLeftoverMapping(defaults: defaults) { cleared += 1 })
            #expect(cleared == 1)
        }
    }

    @Test func quittingTakesTheSuperKeyMappingOutOnlyWhenTheFeatureWasStarted() {
        withRig { r in
            var cleared = 0
            let token = InputKeyboardLane.observeTermination(of: r.binding) { cleared += 1 }
            defer { NotificationCenter.default.removeObserver(token) }
            NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
            #expect(cleared == 1)
            r.registry.switches["superKey"] = false
            NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
            #expect(cleared == 1, "a stopped feature has nothing to put back")
        }
    }
}
