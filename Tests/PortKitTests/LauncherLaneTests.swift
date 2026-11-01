import AppKit
import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import PortKit
@testable import ShellKit

/// Lane W5-D: the quick launcher, the quick toggles and the radial menu bound through `PortFeatureBinding` with a FAKE
/// runtime and a real `FeatureRegistry`. Nothing here registers a hotkey, creates an event tap, restarts the Finder
/// or touches a permission.
@MainActor
@Suite(.serialized) struct LauncherLaneTests {
    static let launcher = "quickLauncher"
    static let toggles = "quickToggles"
    static let radial = "radialMenu"
    static let all = [launcher, toggles, radial]

    final class FakeRuntime {
        var events: [String] = []
        func count(_ event: String) -> Int { events.filter { $0 == event }.count }
        var runtime: LauncherLane.Runtime {
            LauncherLane.Runtime(
                startLauncher: { [self] in events.append("launcher.start") },
                stopLauncher: { [self] in events.append("launcher.stop") },
                startToggles: { [self] in events.append("toggles.start") },
                stopToggles: { [self] in events.append("toggles.stop") },
                startRadial: { [self] in events.append("radial.start") },
                stopRadial: { [self] in events.append("radial.stop") },
                quit: { [self] started in events.append(started ? "quit.started" : "quit.idle") })
        }
    }

    struct Rig {
        let binding: PortFeatureBinding
        let registry: FeatureRegistry
        let fake: FakeRuntime
        let permissions: Box<PortPermissionState>
        let cleanup: () -> Void
    }

    func rig(granted: PortPermissionState = PortPermissionState(accessibility: true), switchedOn: Bool = true) -> Rig {
        let permissions = Box(granted)
        let binding = PortFeatureBinding(permissions: { permissions.value })
        let fake = FakeRuntime()
        LauncherLane.bind(into: binding, runtime: fake.runtime)
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

    @Test func theLaneBindsThreeDescriptorsOffByDefaultWithTheCatalogPermissionsAndRisk() {
        PortHostFixture.isolated { _ in
            let binding = PortFeatureBinding(permissions: { PortPermissionState() })
            LauncherLane.bind(into: binding, runtime: FakeRuntime().runtime)
            #expect(binding.descriptors.map(\.id) == Self.all)
            let table: [String: (permissions: [FeaturePermission], risk: FeatureRisk)] = [
                Self.launcher: ([], .safe),
                Self.toggles: ([.automation], .touchesSystem),
                Self.radial: ([.accessibility], .touchesInput),
            ]
            for d in binding.descriptors {
                let expected = table[d.id]
                #expect(d.permissions == expected?.permissions, "\(d.id)")
                #expect(d.risk == expected?.risk, "\(d.id)")
                #expect(!d.enabledByDefault, "\(d.id) is never on by default")
                #expect(!d.title.isEmpty && !d.summary.isEmpty, "\(d.id) has French text from the hub strings")
            }
            // Idempotent lane: a second bind adds nothing.
            LauncherLane.bind(into: binding, runtime: FakeRuntime().runtime)
            #expect(binding.descriptors.count == 3)
        }
    }

    @Test func eachFeatureBringsOnePageBodyOnAPageOfTheCatalog() {
        PortHostFixture.isolated { _ in
            let binding = PortFeatureBinding(permissions: { PortPermissionState() })
            LauncherLane.bind(into: binding, runtime: FakeRuntime().runtime)
            let pages = Dictionary(uniqueKeysWithValues: binding.pages.map { ($0.featureID, $0.pageID) })
            #expect(pages == [Self.launcher: "quickpanel", Self.toggles: "quickactions", Self.radial: "radial"])
            #expect(LauncherLane.pageIDs == ["quickLauncher": "quickpanel", "quickToggles": "quickactions",
                                             "radialMenu": "radial"])
            for pageID in pages.values {
                #expect(SettingsPageCatalog.page(pageID) != nil, "\(pageID) is a page of ours")
                #expect(SettingsPageCatalog.page(pageID)?.featureID == nil,
                        "\(pageID): the binding adds the feature card, the catalog row carries none")
            }
        }
    }

    @Test func theLaneIsInTheLaneListAndTheAppDelegateStartsNothingOfItsOwn() throws {
        let root = PortSourceScrubTests.repoRoot
        let lanes = try String(contentsOf: root.appendingPathComponent("Sources/PortKit/Bridge/PortLanes.swift"), encoding: .utf8)
        #expect(lanes.contains("LauncherLane.bind(into:),"))
        let delegate = try String(contentsOf: root.appendingPathComponent("Sources/MacIsland/AppDelegate.swift"), encoding: .utf8)
        for service in ["QuickLauncherService", "QuickTogglesService", "RadialMenuService"] {
            #expect(!delegate.contains(service), "\(service) starts only through the registry")
        }
    }

    // MARK: Off by default, permission gate

    @Test func nothingRunsOnAFreshInstallBecauseTheRegistrySwitchesStartOff() {
        PortHostFixture.isolated { _ in
            let r = rig(switchedOn: false)
            defer { r.cleanup() }
            #expect(r.fake.events.isEmpty, "binding and launch start nothing")
            for id in Self.all {
                #expect(r.registry.state(for: id) == .off, "\(id)")
                #expect(r.binding.availability(id) == false, "\(id): the ported code reads 'not available'")
            }
        }
    }

    @Test func theRadialMenuWaitsForAccessibilityAndTheOtherTwoNeedNoGrant() {
        PortHostFixture.isolated { _ in
            let r = rig(granted: PortPermissionState())
            defer { r.cleanup() }
            #expect(r.fake.events.sorted() == ["launcher.start", "toggles.start"],
                    "the radial start is gated, the other two are not: \(r.fake.events)")
            #expect(r.registry.state(for: Self.radial) == .needsPermission(.accessibility))
            #expect(r.registry.state(for: Self.launcher) == .active)
            #expect(r.registry.state(for: Self.toggles) == .active)
            r.fake.events.removeAll()
            change(r, to: PortPermissionState(accessibility: true))
            // The registry restarts a feature on a grant: its stop (idempotent upstream) comes first, then one start.
            #expect(r.fake.events.filter { $0.hasPrefix("radial") } == ["radial.stop", "radial.start"], "the grant starts it")
            #expect(r.fake.count("launcher.start") == 0 && r.fake.count("toggles.start") == 0, "the others are not restarted")
            #expect(r.binding.isStarted(Self.radial))
        }
    }

    @Test func aRevokedAccessibilityRemovesTheRadialTapAndAGrantBringsItBack() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            r.fake.events.removeAll()
            change(r, to: PortPermissionState())
            #expect(r.fake.events.filter { $0.hasPrefix("radial") } == ["radial.stop"], "revoked: hotkeys and tap go")
            #expect(r.fake.count("launcher.stop") == 0 && r.fake.count("toggles.stop") == 0, "the others keep running")
            change(r, to: PortPermissionState(accessibility: true))
            #expect(r.fake.events.last == "radial.start")
        }
    }

    // MARK: Start, stop, kill switch

    @Test func startIsIdempotentAndASecondSwitchOnReachesNothing() {
        PortHostFixture.isolated { _ in
            let r = rig(switchedOn: false)
            defer { r.cleanup() }
            for id in Self.all { r.registry.switches[id] = true }
            for id in Self.all { r.registry.switches[id] = true }
            let before = r.fake.events
            #expect(before.sorted() == ["launcher.start", "radial.start", "toggles.start"])
            for id in Self.all { r.binding.starters[id]!() }
            #expect(r.fake.events == before, "a second start of a running feature reaches nothing")
        }
    }

    @Test func switchingOffStopsEachFeatureOnceAndTheKillSwitchAndSafeModeStopAllThenBringThemBack() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            r.fake.events.removeAll()
            r.registry.switches[Self.radial] = false
            #expect(r.fake.events == ["radial.stop"])
            r.registry.switches[Self.radial] = false
            #expect(r.fake.count("radial.stop") == 1, "a second off changes nothing")
            r.registry.switches[Self.radial] = true
            r.fake.events.removeAll()
            r.registry.killSwitch = true
            #expect(r.fake.events.sorted() == ["launcher.stop", "radial.stop", "toggles.stop"])
            for id in Self.all { #expect(r.binding.availability(id) == false, "\(id): the tap callback sees it at once") }
            r.fake.events.removeAll()
            r.registry.killSwitch = false
            #expect(r.fake.events.sorted() == ["launcher.start", "radial.start", "toggles.start"])
            r.fake.events.removeAll()
            r.registry.safeMode = true
            #expect(r.fake.events.sorted() == ["launcher.stop", "radial.stop", "toggles.stop"])
            for id in Self.all { #expect(!r.binding.isStarted(id), "\(id)") }
        }
    }

    @Test func theUpstreamAvailabilityFollowsTheRegistryNotAStoredKey() {
        PortHostFixture.isolated { defaults in
            let r = rig(switchedOn: false)
            defer { r.cleanup() }
            PortHost.availability = { [binding = r.binding] in binding.availability($0) }
            for feature in [AppFeature.quickLauncher, .quickToggles, .radialMenu] {
                defaults.set(true, forKey: feature.availabilityKey)  // a stale stored switch
                #expect(feature.isAvailable == false, "\(feature)")
            }
            for id in Self.all { r.registry.switches[id] = true }
            #expect(AppFeature.quickLauncher.isAvailable && AppFeature.quickToggles.isAvailable
                    && AppFeature.radialMenu.isAvailable)
            r.registry.killSwitch = true
            #expect(AppFeature.quickToggles.isAvailable == false,
                    "so a toggle on a ported page cannot run an action the registry stopped")
        }
    }

    // MARK: Quit

    @Test func quitTellsTheRuntimeWhetherTheQuickTogglesRan() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            let center = NotificationCenter()
            let token = LauncherLane.observeTermination(of: r.binding, runtime: r.fake.runtime, center: center)
            defer { center.removeObserver(token) }
            r.fake.events.removeAll()
            center.post(name: NSApplication.willTerminateNotification, object: nil)
            #expect(r.fake.events == ["quit.started"])
            r.registry.switches[Self.toggles] = false
            r.fake.events.removeAll()
            center.post(name: NSApplication.willTerminateNotification, object: nil)
            #expect(r.fake.events == ["quit.idle"])
        }
    }
}
