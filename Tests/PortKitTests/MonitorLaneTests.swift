import AppKit
import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import PortKit
@testable import ShellKit

/// Lane W6-A: the seven monitor families bound through `PortFeatureBinding` with a FAKE runtime and a real
/// `FeatureRegistry`. Nothing here samples a sensor, starts the monitor, posts a notification or touches a permission.
@MainActor
@Suite(.serialized) struct MonitorLaneTests {
    static let all = MonitorLane.familyIDs

    final class FakeRuntime {
        var events: [String] = []
        func count(_ event: String) -> Int { events.filter { $0 == event }.count }
        var runtime: MonitorLane.Runtime {
            MonitorLane.Runtime(start: { [self] in events.append("start") }, stop: { [self] in events.append("stop") })
        }
    }

    struct Rig {
        let binding: PortFeatureBinding
        let registry: FeatureRegistry
        let fake: FakeRuntime
        let cleanup: () -> Void
    }

    func rig(switchedOn: Bool = true) -> Rig {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        let fake = FakeRuntime()
        MonitorLane.bind(into: binding, runtime: fake.runtime)
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let probe = PermissionProbe(accessibility: { false }, screenRecording: { false }, inputMonitoring: { false },
                                    automation: { _ in nil })
        let registry = FeatureRegistry(descriptors: binding.descriptors, defaults: bench.defaults, crashMarker: marker,
                                       capabilityProvider: SystemCapabilities.provider(probe), withdraw: { _ in })
        binding.connectAvailability()
        if switchedOn { for d in binding.descriptors { registry.switches[d.id] = true } }
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        return Rig(binding: binding, registry: registry, fake: fake, cleanup: { bench.cleanup(); marker.clear() })
    }

    // MARK: Descriptors and pages

    @Test func theLaneBindsSevenFamiliesOffByDefaultInFrenchWithTheCatalogRiskAndCategory() {
        PortHostFixture.isolated { _ in
            let binding = PortFeatureBinding(permissions: { PortPermissionState() })
            MonitorLane.bind(into: binding, runtime: FakeRuntime().runtime)
            #expect(binding.descriptors.map(\.id) == Self.all)
            #expect(Self.all == ["monitorCPU", "monitorGPU", "monitorMemory", "monitorNetwork", "monitorDisk",
                                 "monitorPower", "connectedDevices"])
            for d in binding.descriptors {
                #expect(!d.enabledByDefault, "\(d.id) is off until the person (or the migrated switch) turns it on")
                #expect(d.category == .monitor, "\(d.id)")
                #expect(d.risk == .safe, "\(d.id) only reads")
                #expect(!d.title.isEmpty && !d.summary.isEmpty, "\(d.id) has French text from the hub strings")
                #expect(d.tabID == nil, "\(d.id): the island card belongs to our own `monitor` feature")
            }
            // Only the notification permission is named, and it is not one the monitor polls: nothing can block a start.
            for d in binding.descriptors {
                #expect(MonitoredPermission.used(by: d).isEmpty, "\(d.id) needs no monitored permission")
            }
            MonitorLane.bind(into: binding, runtime: FakeRuntime().runtime)
            #expect(binding.descriptors.count == Self.all.count, "a second bind adds nothing")
        }
    }

    @Test func theLaneBringsOnePagePlainBodyOnTheMonitorPageOfTheCatalogAndTheGreyedRowsAreGone() {
        MonitorLane.installPage()
        #expect(PortBridge.registeredPageIDs.contains("monitor"))
        #expect(MonitorLane.pageID == "monitor")
        let page = SettingsPageCatalog.page("monitor")
        #expect(page?.featureID == "monitor", "the catalog row keeps carrying OUR monitor card")
        #expect(SettingsLive.controls(for: "monitor") == nil, "the ported body draws the whole page")
        #expect(SettingsLive.isEmpty(pageID: "monitor"))
        // No family brings a page of its own: the page is registered plain, so no second status card appears on it.
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        MonitorLane.bind(into: binding, runtime: FakeRuntime().runtime)
        #expect(binding.pages.isEmpty)
    }

    @Test func theLaneIsInTheLaneListAndTheAppDelegateStartsNothingOfItsOwn() throws {
        let root = PortSourceScrubTests.repoRoot
        let lanes = try String(contentsOf: root.appendingPathComponent("Sources/PortKit/Bridge/PortLanes.swift"), encoding: .utf8)
        #expect(lanes.contains("MonitorLane.bind(into:),"))
        let delegate = try String(contentsOf: root.appendingPathComponent("Sources/MacIsland/AppDelegate.swift"), encoding: .utf8)
        for service in ["SystemMonitor", "MonitorAlertService", "MenuBarMetricsHost"] {
            #expect(!delegate.contains(service), "\(service) starts only through the registry")
        }
        #expect(delegate.contains("PortMenuBar.installAppIconVisibility"), "the one hook the host lends")
    }

    // MARK: Off by default, start, stop

    @Test func nothingRunsOnAFreshInstallBecauseTheRegistrySwitchesStartOff() {
        PortHostFixture.isolated { _ in
            let r = rig(switchedOn: false)
            defer { r.cleanup() }
            #expect(r.fake.events.isEmpty, "binding and launch start nothing")
            for id in Self.all {
                #expect(r.registry.state(for: id) == .off, "\(id)")
                #expect(r.binding.availability(id) == false, "\(id): the ported plan reads 'not available'")
            }
        }
    }

    @Test func eachFamilyStartsOnceWithoutAnyGrantAndStopsOnceWhenSwitchedOff() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            #expect(r.fake.count("start") == Self.all.count, "one start per family, no permission to wait for")
            for id in Self.all { #expect(r.registry.state(for: id) == .active, "\(id)") }
            r.fake.events.removeAll()
            r.registry.switches["monitorCPU"] = false
            #expect(r.fake.events == ["stop"])
            #expect(r.binding.availability("monitorCPU") == false, "the plan sees the family gone when the stop runs")
            #expect(r.binding.availability("monitorGPU") == true, "the others keep running")
            r.registry.switches["monitorCPU"] = false
            #expect(r.fake.count("stop") == 1, "a second off changes nothing")
            for id in Self.all { r.binding.starters[id]!() }
            let afterSecond = r.fake.count("start")
            for id in Self.all { r.binding.starters[id]!() }
            #expect(r.fake.count("start") == afterSecond, "a second start of a running family reaches nothing")
        }
    }

    @Test func theKillSwitchAndSafeModeStopEveryFamilyAndBringThemBack() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            r.fake.events.removeAll()
            r.registry.killSwitch = true
            #expect(r.fake.count("stop") == Self.all.count)
            for id in Self.all { #expect(r.binding.availability(id) == false, "\(id)") }
            r.fake.events.removeAll()
            r.registry.killSwitch = false
            #expect(r.fake.count("start") == Self.all.count)
            r.fake.events.removeAll()
            r.registry.safeMode = true
            #expect(r.fake.count("stop") == Self.all.count)
            for id in Self.all { #expect(!r.binding.isStarted(id), "\(id)") }
        }
    }

    @Test func theUpstreamAvailabilityFollowsTheRegistryAndSoDoesTheMetricGate() {
        PortHostFixture.isolated { defaults in
            let r = rig(switchedOn: false)
            defer { r.cleanup() }
            PortHost.availability = { [binding = r.binding] in binding.availability($0) }
            defaults.set(true, forKey: AppFeature.monitorCPU.availabilityKey)  // a stale stored switch
            defaults.set(true, forKey: MenuBarMetric.cpu.defaultsKey)
            #expect(AppFeature.monitorCPU.isAvailable == false)
            #expect(MenuBarMetric.enabled(in: defaults).isEmpty, "a pinned metric of a family that is off does not render")
            r.registry.switches["monitorCPU"] = true
            #expect(AppFeature.monitorCPU.isAvailable)
            #expect(MenuBarMetric.enabled(in: defaults) == [.cpu])
            r.registry.killSwitch = true
            #expect(MenuBarMetric.enabled(in: defaults).isEmpty)
        }
    }

    // MARK: The live side stays idle until a start reached it

    @Test func theAlertServiceNeverAsksForNotificationsFromALaunchOrARegistryStart() throws {
        let root = PortSourceScrubTests.repoRoot
        let service = try String(contentsOf: root.appendingPathComponent("Sources/PortKit/Services/SystemMonitor/MonitorAlertService.swift"),
                                 encoding: .utf8)
        #expect(service.contains("func syncWithPreferences(askForNotifications: Bool = false)"))
        #expect(service.contains("if enabled, askForNotifications {"), "the prompt is the click's, never the launch's")
        let controls = try String(contentsOf: root.appendingPathComponent("Sources/PortKit/UI/Settings/MonitorAlertsControls.swift"),
                                  encoding: .utf8)
        #expect(!controls.contains("syncWithPreferences();"), "every Settings switch passes askForNotifications: true")
        #expect(controls.components(separatedBy: "syncWithPreferences(askForNotifications: true)").count - 1 == 6)
        let live = try String(contentsOf: root.appendingPathComponent("Sources/PortKit/Bridge/Monitor.swift"), encoding: .utf8)
        #expect(!live.contains("askForNotifications: true"), "the lane never asks")
    }
}
