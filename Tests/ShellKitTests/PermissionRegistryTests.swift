import Foundation
import IslandKit
import IslandTestSupport
import Observation
import Testing
@testable import ShellKit

final class Counter: @unchecked Sendable { var value = 0 }

/// The registry reacts to permission changes. Fakes only: nothing here reads or asks a real permission.
@MainActor
@Suite struct PermissionRegistryTests {
    let bench = TestDefaults.make()
    let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
    let events = Events()

    struct Rig {
        let registry: FeatureRegistry
        let box: SnapshotBox
        let monitor: PermissionMonitor
        let scheduler: FakeScheduler
    }

    func cleanup() { bench.cleanup(); marker.clear() }

    /// Finder uses Accessibility and Input Monitoring; it has a starter and a stopper.
    func rig(_ initial: PermissionSnapshot) -> Rig {
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all, defaults: bench.defaults, crashMarker: marker,
                                       withdraw: { _ in })
        let e = events
        registry.launch(starters: ["finder": { e.list.append("start") }], stoppers: ["finder": { e.list.append("stop") }])
        let box = SnapshotBox(initial)
        let scheduler = FakeScheduler()
        let monitor = PermissionMonitor(
            read: { box.read() }, needed: { [weak registry] in registry?.neededPermissions ?? [] },
            scheduler: scheduler, triggers: nil,
            onChange: { [weak registry] in registry?.permissionsChanged($0) })
        registry.permissionMonitor = monitor
        monitor.start()
        return Rig(registry: registry, box: box, monitor: monitor, scheduler: scheduler)
    }

    func only(ax: Bool = false, im: Bool = false) -> PermissionSnapshot {
        PermissionSnapshot(accessibility: ax, inputMonitoring: im, screenRecording: true)
    }

    @Test func finderNeedsAccessibilityAndInputMonitoring() {
        let finder = ShellDescriptors.all.first { $0.id == "finder" }!
        #expect(MonitoredPermission.used(by: finder) == [.accessibility, .inputMonitoring])
        let dock = ShellDescriptors.all.first { $0.id == "dock" }!
        #expect(MonitoredPermission.used(by: dock) == [.accessibility, .screenRecording])
    }

    @Test func deniedThenGrantedRestartsTheFeatureOnce() {
        defer { cleanup() }
        let r = rig(only())
        #expect(events.list == ["start"], "started at launch, arming nothing")
        r.box.value = only(ax: true, im: true)
        r.monitor.recheck()
        r.monitor.recheck()
        #expect(events.list == ["start", "stop", "start"], "re-armed exactly once")
        #expect(r.registry.running.contains("finder"))
    }

    @Test func grantedThenRevokedStopsTheFeatureAndKeepsItStopped() {
        defer { cleanup() }
        let r = rig(only(ax: true, im: true))
        r.box.value = only(ax: false, im: true)
        r.monitor.recheck()
        #expect(events.list == ["start", "stop"])
        #expect(!r.registry.running.contains("finder"))
        r.registry.refreshCapabilities()  // an unrelated refresh must not bring it back
        r.monitor.recheck()
        #expect(events.list == ["start", "stop"])
    }

    @Test func revokedThenGrantedAgainStartsItWithoutAStop() {
        defer { cleanup() }
        let r = rig(only(ax: true, im: true))
        r.box.value = only(ax: false, im: true)
        r.monitor.recheck()
        r.box.value = only(ax: true, im: true)
        r.monitor.recheck()
        #expect(events.list == ["start", "stop", "start"])
        #expect(r.registry.running.contains("finder"))
    }

    @Test func aFeatureRevokedOnTwoPermissionsStartsOnlyWhenBothAreBack() {
        defer { cleanup() }
        let r = rig(only(ax: true, im: true))
        r.box.value = only(ax: false, im: false)
        r.monitor.recheck()
        r.box.value = only(ax: true, im: false)
        r.monitor.recheck()
        #expect(events.list == ["start", "stop"], "Input Monitoring is still missing")
        r.box.value = only(ax: true, im: true)
        r.monitor.recheck()
        #expect(events.list == ["start", "stop", "start"])
    }

    @Test func aDisabledFeatureIsNotStartedByAGrant() {
        defer { cleanup() }
        let r = rig(only())
        r.registry[feature: "finder"] = false
        #expect(events.list == ["start", "stop"])
        r.box.value = only(ax: true, im: true)
        r.monitor.recheck()
        #expect(events.list == ["start", "stop"])
    }

    @Test func theMonitorPollsOnlyWhileAnEnabledFeatureNeedsAMissingPermission() {
        defer { cleanup() }
        let r = rig(only())
        #expect(r.monitor.isPolling)
        r.registry[feature: "finder"] = false  // nothing enabled needs Input Monitoring any more...
        r.registry[feature: "dock"] = false     // ...nor Accessibility
        r.registry[feature: "display"] = false
        #expect(!r.monitor.isPolling)
        r.registry[feature: "finder"] = true
        #expect(r.monitor.isPolling)
        r.box.value = only(ax: true, im: true)
        r.scheduler.fire()
        #expect(!r.monitor.isPolling)
    }

    @Test func aRealCapabilityChangeIsPublishedAndAnEqualOneIsNot() {
        defer { cleanup() }
        var granted = false
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all, defaults: bench.defaults, crashMarker: marker,
                                       capabilityProvider: { _ in granted ? .available : .needsPermission(.accessibility) },
                                       withdraw: { _ in })
        let publishes = Counter()
        withObservationTracking({ _ = registry.capabilities }, onChange: { publishes.value += 1 })
        registry.refreshCapabilities()
        #expect(publishes.value == 0, "same answer: no publish")
        granted = true
        registry.refreshCapabilities()
        #expect(publishes.value == 1, "a real change is never swallowed")
        #expect(registry.state(for: "finder") == .active)
    }
}
