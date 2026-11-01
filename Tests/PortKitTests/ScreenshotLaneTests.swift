import AppKit
import Foundation
import IslandKit
import IslandTestSupport
import SwiftUI
import Testing
@testable import PortKit
@testable import ShellKit

/// Lane W4-A (screenshot): the screenshot tool bound through `PortFeatureBinding` with a FAKE runtime and FAKE host
/// hooks, so no ScreenCaptureKit call, no hotkey, no window and no permission call is ever made here. Covers the
/// descriptor and permission table, off by default, start and stop through a real `FeatureRegistry` (order, idempotence,
/// kill switch, safe mode, grant and revoke), the host start API, shortcut ownership, and the replacement of our
/// own quick action.
@MainActor
@Suite(.serialized) struct ScreenshotLaneTests {
    static let id = "screenshot"

    final class FakeRuntime {
        var events: [String] = []
        func count(_ event: String) -> Int { events.filter { $0 == event }.count }
        var runtime: ScreenshotLane.Runtime {
            ScreenshotLane.Runtime(
                syncChooser: { [self] in events.append("chooser") },
                syncScreenshot: { [self] in events.append("screenshot") },
                syncRecent: { [self] in events.append("recent") },
                cancelSelection: { [self] in events.append("cancel") },
                removeTemporaryFiles: { [self] in events.append("temp") })
        }
    }

    struct Rig {
        let binding: PortFeatureBinding
        let registry: FeatureRegistry
        let fake: FakeRuntime
        let permissions: Box<PortPermissionState>
        let cleanup: () -> Void
    }

    func rig(granted: PortPermissionState = PortPermissionState(screenRecording: true), switchedOn: Bool = true) -> Rig {
        let permissions = Box(granted)
        let binding = PortFeatureBinding(permissions: { permissions.value })
        let fake = FakeRuntime()
        ScreenshotLane.bind(into: binding, runtime: fake.runtime)
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

    // MARK: Descriptor, permission and page tables

    @Test func theLaneBindsTheScreenshotWithFrenchTextAndScreenRecordingOnly() {
        PortHostFixture.isolated { _ in
            let binding = PortFeatureBinding(permissions: { PortPermissionState() })
            ScreenshotLane.bind(into: binding, runtime: FakeRuntime().runtime)
            #expect(binding.descriptors.map(\.id) == [Self.id])
            let d = binding.descriptors[0]
            #expect(d.category == .tools)
            #expect(d.permissions == [.screenRecording], "Screen Recording is the one gate")
            #expect(d.risk == .safe, "it reads the screen only on demand and writes nothing by itself")
            #expect(!d.enabledByDefault)
            #expect(d.tabID == nil)
            #expect(!d.title.isEmpty && !d.summary.isEmpty)
            #expect(!d.title.lowercased().contains("screenshot") && !d.title.contains("Vorssaint"), "French: \(d.title)")
            ScreenshotLane.bind(into: binding, runtime: FakeRuntime().runtime)
            #expect(binding.descriptors.count == 1, "a second bind of the same feature is refused")
        }
    }

    @Test func thePermissionTableMatchesTheCatalog() {
        #expect(AppFeature.screenshot.permissions == [.screenRecording])
        #expect(AppFeature.screenshot.registryID == Self.id, "a new feature: its registry id is the upstream raw id")
        #expect(!PortFeatureIDs.isOwnedByExistingModule("screenshot"))
        #expect(PortFeatureBinding.featurePermissions(of: .screenshot) == [.screenRecording])
        #expect(PortFeatureBinding.risk(of: .screenshot) == .safe)
        #expect(AppFeature.screenshot.availabilityKey == "shell.enabled.screenshot")
    }

    @Test func thePageIsSettingsRow14AndCarriesTheFeatureCard() {
        PortHostFixture.isolated { _ in
            let binding = PortFeatureBinding(permissions: { PortPermissionState() })
            ScreenshotLane.bind(into: binding, runtime: FakeRuntime().runtime)
            let pages = binding.pages
            #expect(pages.map(\.pageID) == ["screenshot"] && pages.map(\.featureID) == [Self.id])
            #expect(SettingsPageCatalog.page("screenshot")?.title == "Capture d’écran")
        }
    }

    @Test func theLaneIsListedInPortLanes() throws {
        let text = try String(contentsOf: PortSourceScrubTests.portKit.appendingPathComponent("Bridge/PortLanes.swift"),
                              encoding: .utf8)
        #expect(text.contains("ScreenshotLane.bind(into:),"))
    }

    // MARK: Off by default, permission gate

    @Test func nothingRunsUntilTheSwitchIsOn() {
        PortHostFixture.isolated { _ in
            let r = rig(switchedOn: false)
            defer { r.cleanup() }
            #expect(r.fake.events.isEmpty, "binding starts nothing: no service is even built")
            #expect(r.registry.state(for: Self.id) == .off)
            #expect(r.binding.availability(Self.id) == false)
        }
    }

    @Test func nothingStartsWithoutScreenRecordingAndAGrantStartsIt() {
        PortHostFixture.isolated { _ in
            let r = rig(granted: PortPermissionState())
            defer { r.cleanup() }
            #expect(r.fake.events.isEmpty, "switched on, Screen Recording missing: no service was touched")
            #expect(r.registry.state(for: Self.id) == .needsPermission(.screenRecording))
            change(r, to: PortPermissionState(screenRecording: true))
            #expect(r.binding.isStarted(Self.id))
            // The registry restarts the features of a permission on a grant: an idempotent stop, then the start.
            #expect(Array(r.fake.events.suffix(3)) == ["screenshot", "chooser", "recent"])
            #expect(r.fake.count("chooser") == 2 && r.fake.count("cancel") == 1)
            // A revoke stops it, and nothing restarts while it is missing.
            r.fake.events.removeAll()
            change(r, to: PortPermissionState())
            #expect(r.fake.events == ["cancel", "screenshot", "chooser", "recent", "temp"])
            #expect(r.binding.availability(Self.id) == false)
        }
    }

    @Test func accessibilityIsNotNeededToCapture() {
        PortHostFixture.isolated { _ in
            let r = rig(granted: PortPermissionState(accessibility: false, screenRecording: true))
            defer { r.cleanup() }
            #expect(r.binding.isStarted(Self.id), "window attachment uses Accessibility when granted, never requires it")
        }
    }

    // MARK: Start, stop, kill switch

    @Test func startIsIdempotentAndStopClosesTheOverlayBeforeAnythingElse() {
        PortHostFixture.isolated { _ in
            let r = rig(switchedOn: false)
            defer { r.cleanup() }
            r.registry.switches[Self.id] = true
            r.registry.switches[Self.id] = true
            #expect(r.fake.events == ["screenshot", "chooser", "recent"], "one start")
            #expect(r.binding.availability(Self.id) == true)
            r.fake.events.removeAll()
            r.registry.switches[Self.id] = false
            #expect(r.fake.events == ["cancel", "screenshot", "chooser", "recent", "temp"],
                    "the overlay first (it holds the screen), then the services re-read a false availability")
            #expect(r.binding.availability(Self.id) == false)
            r.registry.switches[Self.id] = false
            #expect(r.fake.count("cancel") == 1, "a second off changes nothing")
        }
    }

    @Test func theStopNeverSuspendsTheSharedChooserOtherToolsUse() throws {
        let text = try String(contentsOf: PortSourceScrubTests.portKit.appendingPathComponent("Bridge/Screenshot.swift"),
                              encoding: .utf8)
        #expect(!text.contains("ScreenCaptureService.shared.suspend()"),
                "suspend() drops the recorder, text and colour shortcuts: a stop re-syncs instead")
        #expect(text.contains("cancelActiveSelection()"))
    }

    @Test func killSwitchSafeModeAndQuarantineStopEverythingAndTheFeatureComesBack() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            #expect(r.fake.events == ["screenshot", "chooser", "recent"])
            r.fake.events.removeAll()
            r.registry.killSwitch = true
            #expect(r.fake.events == ["cancel", "screenshot", "chooser", "recent", "temp"], "the kill switch closes the overlay")
            #expect(r.binding.availability(Self.id) == false)
            r.fake.events.removeAll()
            r.registry.killSwitch = false
            #expect(r.fake.events == ["screenshot", "chooser", "recent"])
            r.fake.events.removeAll()
            r.registry.safeMode = true
            #expect(r.fake.count("cancel") == 1, "safe mode stops it too")
            #expect(r.binding.availability(Self.id) == false)
        }
    }

    @Test func theUpstreamServicesFollowTheRegistryVerdictNotAStoredKey() {
        PortHostFixture.isolated { defaults in
            let r = rig(switchedOn: false)
            defer { r.cleanup() }
            PortHost.availability = { [binding = r.binding] in binding.availability($0) }
            defaults.set(true, forKey: AppFeature.screenshot.availabilityKey)  // a stale stored switch
            #expect(AppFeature.screenshot.isAvailable == false)
            r.registry.switches[Self.id] = true
            #expect(AppFeature.screenshot.isAvailable)
            r.registry.killSwitch = true
            #expect(AppFeature.screenshot.isAvailable == false, "a toggle on a ported page cannot restart a stopped tool")
        }
    }

    // MARK: The host's start API

    final class FakeHost {
        var running = true
        var screenRecording = true
        var busy = false
        var events: [String] = []
        var hooks: PortScreenshot.Hooks {
            PortScreenshot.Hooks(
                isRunning: { [self] in running }, hasScreenRecording: { [self] in screenRecording },
                isBusy: { [self] in busy },
                startArea: { [self] in events.append("area") }, startScrolling: { [self] in events.append("scrolling") },
                showRecent: { [self] in events.append("recent") })
        }
    }

    @Test func startResultTableAndNothingStartsWhenRefused() {
        let host = FakeHost()
        let saved = PortScreenshot.hooks
        defer { PortScreenshot.hooks = saved }
        PortScreenshot.hooks = host.hooks

        #expect(PortScreenshot.beginAreaCapture() == .started)
        #expect(host.events == ["area"])
        host.events.removeAll()

        host.busy = true
        #expect(PortScreenshot.beginAreaCapture() == .busy)
        host.busy = false
        host.screenRecording = false
        #expect(PortScreenshot.beginAreaCapture() == .needsScreenRecording)
        #expect(PortScreenshot.beginScrollingCapture() == .needsScreenRecording)
        host.running = false
        #expect(PortScreenshot.beginAreaCapture() == .featureOff, "off wins: the host falls back to its own tool")
        #expect(PortScreenshot.beginScrollingCapture() == .featureOff)
        #expect(host.events.isEmpty, "a refusal never reaches the chooser")

        host.running = true
        host.screenRecording = true
        #expect(PortScreenshot.beginScrollingCapture() == .started)
        PortScreenshot.showRecentCaptures()
        host.running = false
        PortScreenshot.showRecentCaptures()
        #expect(host.events == ["scrolling", "recent"], "the palette is silent while the feature is off")
    }

    @Test func theLiveHooksReadTheRegistryAndThePermissionMonitorOnly() {
        PortHostFixture.isolated { _ in
            let live = PortScreenshot.Hooks.live
            #expect(live.isRunning() == false, "no binding yet: not running")
            PortHost.availability = { $0 == "screenshot" ? true : nil }
            #expect(live.isRunning())
            PortHost.availability = { _ in false }
            #expect(!live.isRunning())
            #expect(live.hasScreenRecording() == false)
            PortHost.permissionState.send(PortPermissionState(screenRecording: true))
            #expect(live.hasScreenRecording())
        }
    }

    // MARK: Shortcut ownership

    @Test func theCaptureShortcutsHaveOneOwnerTheRegistryRunsThem() {
        PortHostFixture.isolated { _ in
            let r = rig(switchedOn: false)
            defer { r.cleanup() }
            #expect(PortShortcutOwnership.isBound(.screenshot), "bound: the central editor lists the capture rows")
            #expect(!PortShortcutOwnership.isRunning(.screenshot))
            r.registry.switches[Self.id] = true
            #expect(PortShortcutOwnership.isRunning(.screenshot))
            r.registry.killSwitch = true
            #expect(!PortShortcutOwnership.isRunning(.screenshot), "off: the hotkeys are gone and the rows with them")
        }
    }

    // MARK: Replacing our quick action

    @Test func theQuickActionRouteIsPortedWhileTheToolRunsAndLegacyOtherwise() {
        #expect(QuickCaptureRoute.route(portedRunning: true, screenRecording: true) == .ported)
        #expect(QuickCaptureRoute.route(portedRunning: true, screenRecording: false) == .needsScreenRecording)
        #expect(QuickCaptureRoute.route(portedRunning: false, screenRecording: true) == .legacy)
        #expect(QuickCaptureRoute.route(portedRunning: false, screenRecording: false) == .legacy,
                "off: the old button keeps working and asks for the grant itself")
    }

    @Test func theHomeTileAndTheQuickAccessButtonAreRepointedToTheToolAndStayTheSameButton() throws {
        let root = PortSourceScrubTests.repoRoot
        let actions = try String(contentsOf: root.appendingPathComponent("Sources/MacIsland/SystemActions.swift"),
                                 encoding: .utf8)
        #expect(actions.contains("QuickCaptureRoute.route(portedRunning: PortScreenshot.isRunning"))
        #expect(actions.contains("PortScreenshot.beginAreaCapture()"))
        #expect(actions.contains("captureWithSystemTool()"), "the fallback is kept, so the tile is never dead")
        let delegate = try String(contentsOf: root.appendingPathComponent("Sources/MacIsland/AppDelegate.swift"),
                                  encoding: .utf8)
        #expect(delegate.contains("table.register(\"capture\") { actions.capture() }"), "same key, same tile")
        let home = try String(contentsOf: root.appendingPathComponent("Sources/ShellKit/Home/HomeAction.swift"),
                              encoding: .utf8)
        #expect(home.contains("id: \"capture\"") && home.contains("\"control.screenshot\": \"capture\""))
        let access = try String(contentsOf: root.appendingPathComponent("Sources/ShellKit/QuickAccess.swift"),
                                encoding: .utf8)
        #expect(access.contains("id: \"capture\""))
        // The old tool still builds the same arguments, from fixed strings, no shell.
        #expect(ScreenshotPlan.arguments(file: URL(fileURLWithPath: "/tmp/x.png")) == ["-i", "-t", "png", "/tmp/x.png"])
    }

    @Test func theRegisteredActionKeysExist() {
        PortHostFixture.isolated { _ in
            let binding = PortFeatureBinding(permissions: { PortPermissionState() })
            ScreenshotLane.bind(into: binding)
            for key in ["screenshot.area", "screenshot.scrolling", "screenshot.recent"] {
                #expect(PortBridge.action(forKey: key) != nil, "\(key)")
            }
        }
    }
}
