import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import ShellKit

@MainActor
@Suite struct FeatureRegistryTests {
    let bench = TestDefaults.make()
    var defaults: UserDefaults { bench.defaults }

    func registry(_ provider: @escaping (FeatureDescriptor) -> FeatureCapability = { _ in .available }) -> FeatureRegistry {
        FeatureRegistry(descriptors: ShellDescriptors.all, defaults: defaults, capabilityProvider: provider)
    }

    @Test func defaultsFollowDescriptorsAndSwitchPersists() {
        defer { bench.cleanup() }
        let r = registry()
        #expect(r.isEnabled("terminal"))
        r.switches["terminal"] = false
        #expect(r.state(for: "terminal") == .off)
        #expect(registry().state(for: "terminal") == .off)  // a fresh registry reads the stored switch
    }

    @Test func killSwitchStopsEverythingAndPersists() {
        defer { bench.cleanup() }
        let r = registry()
        r.killSwitch = true
        #expect(ShellDescriptors.all.allSatisfy { r.state(for: $0.id) == .killed })
        #expect(registry().killSwitch)
    }

    @Test func safeModeKeepsOnlyDailyFeatures() {
        defer { bench.cleanup() }
        let r = registry()
        r.safeMode = true
        for d in ShellDescriptors.all {
            #expect(r.isEnabled(d.id) == (d.category == .daily), "\(d.id)")
        }
        #expect(r.state(for: "dock") == .safeMode)
    }

    @Test func quarantineAfterTwoCrashedStarts() {
        defer { bench.cleanup() }
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
        defer { bench.cleanup() }
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
        defer { bench.cleanup() }
        let r = registry()
        r.switches["dock"] = false
        var started: [String] = []
        r.launch(starters: ["clipboard": { started.append("clipboard") }, "dock": { started.append("dock") },
                            "finder": { started.append("finder") }])
        #expect(started == ["clipboard", "finder"])
        #expect(defaults.string(forKey: FeatureRegistry.Keys.starting) == nil)
    }

    @Test func launchFlagIsSetWhileStartRuns() {
        defer { bench.cleanup() }
        let r = registry()
        var seen: String?
        let d = defaults
        r.launch(starters: ["dock": { seen = d.string(forKey: FeatureRegistry.Keys.starting) }])
        #expect(seen == "dock")
    }

    @Test func capabilityProviderDrivesState() {
        defer { bench.cleanup() }
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
        defer { bench.cleanup() }
        var granted = false
        let r = registry { _ in granted ? .available : .needsPermission(.accessibility) }
        #expect(r.state(for: "finder") == .needsPermission(.accessibility))
        granted = true
        r.refreshCapabilities()
        #expect(r.state(for: "finder") == .active)
    }

    @Test func precedenceKillThenQuarantineThenSafeThenOff() {
        defer { bench.cleanup() }
        let r = registry()
        r.switches["dock"] = false
        #expect(r.state(for: "dock") == .off)
        r.safeMode = true
        #expect(r.state(for: "dock") == .safeMode)
        r.killSwitch = true
        #expect(r.state(for: "dock") == .killed)
    }

    @Test func bundlesApplySetsOfSwitches() {
        defer { bench.cleanup() }
        let r = registry()
        r.apply(.essentiel)
        #expect(r.isEnabled("terminal") && r.isEnabled("monitor"))
        #expect(!r.isEnabled("dock") && !r.isEnabled("finder") && !r.isEnabled("fans"))
        r.apply(.productivite)
        #expect(r.isEnabled("dock") && r.isEnabled("shelf") && !r.isEnabled("display"))
        r.apply(.tout)
        #expect(ShellDescriptors.all.allSatisfy { r.isEnabled($0.id) })
    }

    @Test func unknownFeatureIsUnavailable() {
        defer { bench.cleanup() }
        #expect(registry().state(for: "nope") == .unavailable(reason: "Fonction inconnue"))
    }
}
