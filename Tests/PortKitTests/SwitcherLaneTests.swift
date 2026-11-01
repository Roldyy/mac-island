import AppKit
import Foundation
import IslandKit
import IslandTestSupport
import SwiftUI
import Testing
@testable import PortKit
@testable import ShellKit

/// Lane W3-A (switcher): the switcher bound through `PortFeatureBinding` with a FAKE runtime, so no event tap, no
/// window-server call and no Accessibility call is ever made here. Covers the descriptor, off by default, the
/// permission gate (Accessibility only: Screen Recording never blocks the start), start and stop through the
/// registry, the kill switch, safe mode, quit and the Settings page.
@MainActor
@Suite(.serialized) struct SwitcherLaneTests {
    static let id = "switcher"

    final class FakeRuntime {
        var events: [String] = []
        func count(_ event: String) -> Int { events.filter { $0 == event }.count }
        var runtime: SwitcherLane.Runtime {
            SwitcherLane.Runtime(
                start: { [self] in events.append("start") },
                stop: { [self] in events.append("stop") },
                quit: { [self] wasStarted in events.append(wasStarted ? "quitStarted" : "quitIdle") })
        }
    }

    struct Rig {
        let binding: PortFeatureBinding
        let registry: FeatureRegistry
        let fake: FakeRuntime
        let permissions: Box<PortPermissionState>
        let cleanup: () -> Void
    }

    func rig(granted: PortPermissionState = PortPermissionState(accessibility: true, screenRecording: true),
             switchedOn: Bool = true) -> Rig {
        let permissions = Box(granted)
        let binding = PortFeatureBinding(permissions: { permissions.value })
        let fake = FakeRuntime()
        SwitcherLane.bind(into: binding, runtime: fake.runtime)
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let probe = PermissionProbe(accessibility: { permissions.value.accessibility },
                                    screenRecording: { permissions.value.screenRecording },
                                    inputMonitoring: { permissions.value.inputMonitoring }, automation: { _ in nil })
        let registry = FeatureRegistry(descriptors: binding.descriptors, defaults: bench.defaults, crashMarker: marker,
                                       capabilityProvider: SystemCapabilities.provider(probe), withdraw: { _ in })
        binding.connectAvailability()
        if switchedOn { for d in binding.descriptors { registry.switches[d.id] = true } }
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        return Rig(binding: binding, registry: registry, fake: fake, permissions: permissions,
                   cleanup: { bench.cleanup(); marker.clear() })
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

    // MARK: Descriptor

    @Test func theLaneBindsTheSwitcherWithFrenchTextAndAccessibilityOnly() {
        PortHostFixture.isolated { _ in
            let binding = PortFeatureBinding(permissions: { PortPermissionState() })
            SwitcherLane.bind(into: binding, runtime: FakeRuntime().runtime)
            #expect(binding.descriptors.map(\.id) == [Self.id])
            let d = binding.descriptors[0]
            #expect(d.category == .windows)
            #expect(d.permissions == [.accessibility], "Screen Recording is not a start gate: thumbnails degrade to icons")
            #expect(d.risk == .touchesInput)
            #expect(!d.enabledByDefault)
            #expect(!d.title.isEmpty && !d.summary.isEmpty)
            #expect(!d.title.lowercased().contains("switcher"), "French, not English: \(d.title)")
            // A second bind of the same feature is refused (idempotent lane).
            SwitcherLane.bind(into: binding, runtime: FakeRuntime().runtime)
            #expect(binding.descriptors.count == 1)
        }
    }

    @Test func theLaneIsListedInPortLanes() throws {
        let text = try String(contentsOf: PortSourceScrubTests.portKit.appendingPathComponent("Bridge/PortLanes.swift"),
                              encoding: .utf8)
        #expect(text.contains("SwitcherLane.bind(into:),"))
    }

    // MARK: Off by default, permission gate

    @Test func nothingRunsUntilTheSwitchIsOn() {
        PortHostFixture.isolated { _ in
            let r = rig(switchedOn: false)
            defer { r.cleanup() }
            #expect(r.fake.events.isEmpty)
            #expect(r.registry.state(for: Self.id) == .off)
            #expect(r.binding.availability(Self.id) == false, "the ported code reads 'not available'")
        }
    }

    @Test func nothingStartsWithoutAccessibilityAndAGrantStartsIt() {
        PortHostFixture.isolated { _ in
            let r = rig(granted: PortPermissionState())
            defer { r.cleanup() }
            #expect(r.fake.events.isEmpty, "switched on, Accessibility missing: no service was touched")
            #expect(r.registry.state(for: Self.id) == .needsPermission(.accessibility))
            change(r, to: PortPermissionState(accessibility: true))
            #expect(r.binding.isStarted(Self.id))
            #expect(r.fake.events.last == "start")
        }
    }

    @Test func screenRecordingMissingDoesNotBlockTheStart() {
        PortHostFixture.isolated { _ in
            let r = rig(granted: PortPermissionState(accessibility: true, screenRecording: false))
            defer { r.cleanup() }
            #expect(r.fake.count("start") == 1, "icons-only: the switcher runs without Screen Recording")
            #expect(r.registry.state(for: Self.id) == .active)
            // Granting or revoking Screen Recording later neither stops nor restarts it.
            r.fake.events.removeAll()
            change(r, to: PortPermissionState(accessibility: true, screenRecording: true))
            change(r, to: PortPermissionState(accessibility: true, screenRecording: false))
            #expect(r.fake.events.isEmpty)
        }
    }

    @Test func startIsIdempotent() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            let before = r.fake.events
            r.binding.starters[Self.id]!()
            #expect(r.fake.events == before, "a second start of a running feature reaches nothing")
        }
    }

    // MARK: Stops

    @Test func theKillSwitchAndSafeModeStopItAndLiftingStartsItAgain() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            r.fake.events.removeAll()
            r.registry.killSwitch = true
            #expect(r.fake.events == ["stop"])
            #expect(r.registry.state(for: Self.id) == .killed)
            #expect(r.binding.availability(Self.id) == false, "the tap callback sees 'unavailable' at once")
            r.registry.killSwitch = false
            #expect(r.fake.events == ["stop", "start"])
            r.fake.events.removeAll()
            r.registry.safeMode = true
            #expect(r.fake.events == ["stop"])
            #expect(!r.binding.isStarted(Self.id))
        }
    }

    @Test func switchingItOffStopsItAndARevokeStopsItUntilTheGrantIsBack() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            r.fake.events.removeAll()
            change(r, to: PortPermissionState(screenRecording: true))
            #expect(r.fake.events == ["stop"], "Accessibility revoked")
            r.fake.events.removeAll()
            change(r, to: PortPermissionState(accessibility: true, screenRecording: true))
            #expect(r.fake.events.last == "start")
            r.fake.events.removeAll()
            r.registry.switches[Self.id] = false
            #expect(r.fake.events == ["stop"])
        }
    }

    // MARK: Start behind the probe

    @Test func aBlockingProbeNeverReachesTheService() {
        var synced = 0
        let blocked = SwitcherProbe.evaluate { $0 != "_AXUIElementGetWindow" }
        SwitcherLane.start(probe: blocked) { synced += 1 }
        #expect(synced == 0, "no tap in front of the keyboard when windows cannot be mapped")
        let degraded = SwitcherProbe.evaluate { $0 != "CGSHWCaptureWindowList" }
        SwitcherLane.start(probe: degraded) { synced += 1 }
        #expect(synced == 1, "a missing thumbnail call only degrades")
    }

    // MARK: Quit

    @Test func quitGivesTheShortcutBackWhetherOrNotTheSwitcherRan() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            let center = NotificationCenter()
            let token = SwitcherLane.observeTermination(of: r.binding, runtime: r.fake.runtime, center: center)
            defer { center.removeObserver(token) }
            r.fake.events.removeAll()
            center.post(name: NSApplication.willTerminateNotification, object: nil)
            #expect(r.fake.events == ["quitStarted"])
            r.registry.killSwitch = true
            r.fake.events.removeAll()
            center.post(name: NSApplication.willTerminateNotification, object: nil)
            #expect(r.fake.events == ["quitIdle"], "still reaches the restore, which is unconditional on the live runtime")
        }
    }

    // MARK: Settings page

    @Test func thePageReplacesTheComingSoonRowsAndRendersWhileOff() {
        PortHostFixture.isolated { _ in
            SettingsPageBodies.removeAll()
            defer { SettingsPageBodies.removeAll() }
            let r = rig(switchedOn: false)
            defer { r.cleanup() }
            let pages = r.binding.pages
            #expect(pages.map(\.pageID) == [SwitcherLane.pageID])
            #expect(pages.map(\.featureID) == [Self.id])
            let ported = pages[0]
            let page = SettingsPageCatalog.page(ported.pageID)!
            #expect(page.isComingSoon, "a stub until the body is registered")
            SettingsPageBodies.register(pageID: ported.pageID, featureID: ported.featureID, registry: r.registry,
                                        openPermission: { _ in }, ported.body)
            #expect(!page.isComingSoon)
            #expect(SettingsPageModel.blocks(for: page).isEmpty, "no greyed 'Bientôt' row stays under the body")
            let host = NSHostingView(rootView: ported.body())
            host.frame = NSRect(x: 0, y: 0, width: 720, height: 900)
            host.layoutSubtreeIfNeeded()
            #expect(host.fittingSize.height > 40, "rendered \(host.fittingSize): empty while the feature is off")
        }
    }
}
