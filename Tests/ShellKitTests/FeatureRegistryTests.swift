import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import ShellKit

@MainActor
@Suite struct FeatureRegistryTests {
    let bench = TestDefaults.make()
    var defaults: UserDefaults { bench.defaults }
    let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
    let log = WithdrawLog()

    func cleanup() { bench.cleanup(); marker.clear() }

    func registry(_ provider: @escaping (FeatureDescriptor) -> FeatureCapability = { _ in .available }) -> FeatureRegistry {
        FeatureRegistry(descriptors: ShellDescriptors.all, defaults: defaults, crashMarker: marker,
                        capabilityProvider: provider, withdraw: { [log] in log.withdrawn.append($0) })
    }

    @Test func defaultsFollowDescriptorsAndSwitchPersists() {
        defer { cleanup() }
        let r = registry()
        #expect(r.isEnabled("terminal"))
        r.switches["terminal"] = false
        #expect(r.state(for: "terminal") == .off)
        #expect(registry().state(for: "terminal") == .off)  // a fresh registry reads the stored switch
    }

    @Test func killSwitchStopsEverythingAndPersists() {
        defer { cleanup() }
        let r = registry()
        r.killSwitch = true
        #expect(ShellDescriptors.all.allSatisfy { r.state(for: $0.id) == .killed })
        #expect(registry().killSwitch)
    }

    @Test func safeModeKeepsOnlyDailyFeatures() {
        defer { cleanup() }
        let r = registry()
        r.safeMode = true
        for d in ShellDescriptors.all {
            #expect(r.isEnabled(d.id) == (d.category == .daily), "\(d.id)")
        }
        #expect(r.state(for: "dock") == .safeMode)
    }

    @Test func quarantineAfterTwoCrashedStarts() {
        defer { cleanup() }
        var r = registry()
        r.beginStart("dock")  // crash: no endStart
        r = registry()
        #expect(r.state(for: "dock") == .active, "one crash is not enough")
        r.beginStart("dock")  // second crash
        r = registry()
        #expect(r.state(for: "dock") == .quarantined)
        #expect(r.quarantined == ["dock"])
        r.clearQuarantine("dock")
        #expect(r.state(for: "dock") == .active)
        #expect(registry().state(for: "dock") == .active)
    }

    @Test func cleanStartResetsCrashHistory() {
        defer { cleanup() }
        var r = registry()
        r.beginStart("dock")
        r = registry()  // one crash on record
        r.beginStart("dock")
        r.endStart("dock")
        r.beginStart("dock")  // a later crash counts as the first again
        r = registry()
        #expect(r.state(for: "dock") == .active)
    }

    @Test func launchStartsOnlyEnabledFeaturesInOrderAndClearsFlag() {
        defer { cleanup() }
        let r = registry()
        r.switches["dock"] = false
        var started: [String] = []
        r.launch(starters: ["clipboard": { started.append("clipboard") }, "dock": { started.append("dock") },
                            "finder": { started.append("finder") }])
        #expect(started == ["clipboard", "finder"])
        #expect(marker.pending() == nil)
    }

    @Test func launchFlagIsSetWhileStartRuns() {
        defer { cleanup() }
        let r = registry()
        var seen: String?
        let m = marker
        r.launch(starters: ["dock": { seen = m.pending() }])
        #expect(seen == "dock")
    }

    @Test func capabilityProviderDrivesState() {
        defer { cleanup() }
        let r = registry { d in
            switch d.id {
            case "dock": .needsPermission(.accessibility)
            case "fans": .unavailable(reason: "Pas de ventilateur")
            default: .available
            }
        }
        #expect(r.state(for: "dock") == .needsPermission(.accessibility))
        #expect(r.isEnabled("dock"))  // still started: start() arms only what is granted
        #expect(r.state(for: "fans") == .unavailable(reason: "Pas de ventilateur"))
        #expect(!r.isEnabled("fans"))
        #expect(r.state(for: "terminal") == .active)
    }

    @Test func refreshPicksUpAGrantedPermission() {
        defer { cleanup() }
        var granted = false
        let r = registry { _ in granted ? .available : .needsPermission(.accessibility) }
        #expect(r.state(for: "finder") == .needsPermission(.accessibility))
        granted = true
        r.refreshCapabilities()
        #expect(r.state(for: "finder") == .active)
    }

    @Test func precedenceKillThenQuarantineThenSafeThenOff() {
        defer { cleanup() }
        let r = registry()
        r.switches["dock"] = false
        #expect(r.state(for: "dock") == .off)
        r.safeMode = true
        #expect(r.state(for: "dock") == .safeMode)
        r.killSwitch = true
        #expect(r.state(for: "dock") == .killed)
    }

    @Test func bundlesApplySetsOfSwitches() {
        defer { cleanup() }
        let r = registry()
        r.apply(.essentiel)
        #expect(r.isEnabled("terminal") && r.isEnabled("monitor"))
        #expect(!r.isEnabled("dock") && !r.isEnabled("finder") && !r.isEnabled("fans"))
        r.apply(.productivite)
        #expect(r.isEnabled("dock") && r.isEnabled("shelf"))
        r.apply(.tout)
        #expect(ShellDescriptors.all.allSatisfy { r.isEnabled($0.id) })
    }

    @Test func unknownFeatureIsUnavailable() {
        defer { cleanup() }
        #expect(registry().state(for: "nope") == .unavailable(reason: "Fonction inconnue"))
    }

    // MARK: - Live start and stop

    /// Starters and stoppers for the given ids that only record what ran, in order.
    private func hooks(_ ids: [String], events: Events)
        -> (starters: [String: @MainActor () -> Void], stoppers: [String: @MainActor () -> Void]) {
        var starters: [String: @MainActor () -> Void] = [:]
        var stoppers: [String: @MainActor () -> Void] = [:]
        for id in ids {
            starters[id] = { events.list.append("start \(id)") }
            stoppers[id] = { events.list.append("stop \(id)") }
        }
        return (starters, stoppers)
    }

    @Test func killSwitchCallsEveryRegisteredStopAndWithdrawsThenRestarts() {
        defer { cleanup() }
        let r = registry()
        let ids = ["dock", "finder", "monitor", "agents"]
        let events = Events()
        let h = hooks(ids, events: events)
        r.launch(starters: h.starters, stoppers: h.stoppers, activitySources: ["agents": "claude"])
        events.list.removeAll()

        r.killSwitch = true
        #expect(Set(events.list) == Set(ids.map { "stop \($0)" }))
        #expect(Set(log.withdrawn) == ["dock", "finder", "monitor", "claude"], "source names, claude for agents")
        #expect(r.running.isEmpty)

        events.list.removeAll()
        r.killSwitch = false
        #expect(Set(events.list) == Set(ids.map { "start \($0)" }))
        #expect(r.running == Set(ids))
    }

    @Test func killSwitchIsIdempotentAndNeverStopsTwice() {
        defer { cleanup() }
        let r = registry()
        let events = Events()
        let h = hooks(["dock"], events: events)
        r.launch(starters: h.starters, stoppers: h.stoppers)
        events.list.removeAll()
        r.killSwitch = true
        r.safeMode = true  // still not wanted: nothing more to stop
        r.switches["dock"] = false
        #expect(events.list == ["stop dock"])
    }

    @Test func safeModeStopsOnlyNonDailyFeatures() {
        defer { cleanup() }
        let r = registry()
        let events = Events()
        let h = hooks(["clipboard", "dock", "fans"], events: events)  // clipboard is daily
        r.launch(starters: h.starters, stoppers: h.stoppers)
        events.list.removeAll()
        r.safeMode = true
        #expect(Set(events.list) == ["stop dock", "stop fans"])
        events.list.removeAll()
        r.safeMode = false
        #expect(Set(events.list) == ["start dock", "start fans"])
    }

    @Test func aSwitchStartsAndStopsItsFeatureLive() {
        defer { cleanup() }
        let r = registry()
        let events = Events()
        let h = hooks(["dock"], events: events)
        r.switches["dock"] = false  // before launch: nothing runs, nothing to reconcile
        r.launch(starters: h.starters, stoppers: h.stoppers)
        #expect(events.list.isEmpty)
        r[feature: "dock"] = true
        #expect(events.list == ["start dock"])
        r[feature: "dock"] = false
        #expect(events.list == ["start dock", "stop dock"])
        #expect(log.withdrawn == ["dock"])
    }

    @Test func aFeatureWithoutStopperNeedsARelaunch() {
        defer { cleanup() }
        let r = registry()
        let events = Events()
        let h = hooks(["dock"], events: events)
        r.launch(starters: h.starters.merging(["shelf": { events.list.append("start shelf") }]) { a, _ in a },
                 stoppers: h.stoppers)
        #expect(!r.needsRelaunch("shelf"))
        r[feature: "shelf"] = false
        #expect(r.needsRelaunch("shelf"))
        #expect(!r.needsRelaunch("dock"), "dock has a stopper")
        #expect(!events.list.contains("stop shelf"))
        #expect(!log.withdrawn.contains("shelf"), "a still-running feature would just repost")
        r.killSwitch = true
        #expect(r.needsRelaunch("shelf"))
        r.killSwitch = false
        r[feature: "shelf"] = true
        #expect(!r.needsRelaunch("shelf"))
        #expect(events.list.filter { $0 == "start shelf" }.count == 1, "never started twice")
    }

    @Test func aGrantedPermissionStartsAFeatureThatWasUnavailable() {
        defer { cleanup() }
        var available = false
        let r = registry { _ in available ? .available : .unavailable(reason: "Pas prêt") }
        let events = Events()
        let h = hooks(["dock"], events: events)
        r.launch(starters: h.starters, stoppers: h.stoppers)
        #expect(events.list.isEmpty)
        available = true
        r.refreshCapabilities()
        #expect(events.list == ["start dock"])
    }

    @Test func aLiveStartIsWrappedInTheCrashMarker() {
        defer { cleanup() }
        let r = registry()
        r.switches["dock"] = false
        let m = marker
        var seen: String?
        r.launch(starters: ["dock": { seen = m.pending() }], stoppers: ["dock": {}])
        r[feature: "dock"] = true
        #expect(seen == "dock")
        #expect(marker.pending() == nil)
    }
}

@MainActor final class Events { var list: [String] = [] }
@MainActor final class WithdrawLog { var withdrawn: [String] = [] }
