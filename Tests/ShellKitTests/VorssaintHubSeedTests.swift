import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import ShellKit

@MainActor
@Suite struct VorssaintHubSeedTests {
    @Test func parsesEveryPlausibleShape() throws {
        #expect(VorssaintHubSeed.tokens(in: "superKey, dock;clipboard") == ["superKey", "dock", "clipboard"])
        #expect(VorssaintHubSeed.tokens(in: ["a", "b"]) == ["a", "b"])
        #expect(VorssaintHubSeed.tokens(in: ["a": true, "b": false]) == ["a"])
        let json = try JSONSerialization.data(withJSONObject: ["mixer", "dock"])
        #expect(VorssaintHubSeed.tokens(in: json) == ["mixer", "dock"])
        #expect(VorssaintHubSeed.tokens(in: nil).isEmpty)
        #expect(VorssaintHubSeed.tokens(in: 42).isEmpty)
        #expect(VorssaintHubSeed.tokens(in: Data([0xFF, 0x00])).isEmpty)
    }

    @Test func matchesIdsTitlesAndAliasesIgnoringCaseAndAccents() {
        let ids = VorssaintHubSeed.featureIDs(
            in: "superKey etagere Mixer PRESSE-PAPIERS KeepAwake nothing", descriptors: ShellDescriptors.all)
        #expect(ids == ["shelf", "audio", "clipboard", "keepawake"])
    }

    @Test func seedEnablesNamedFeaturesOnceAndNeverOverridesTheUser() {
        let b = TestDefaults.make(); defer { b.cleanup() }
        // Dock is off by user choice; display is off by an earlier hub choice; finder is untouched.
        b.defaults.set(false, forKey: FeatureRegistry.Keys.enabled("dock"))
        let r = FeatureRegistry(descriptors: ShellDescriptors.all, defaults: b.defaults)
        r.switches["finder"] = false
        #expect(r.seedFromVorssaint("dock finder"))
        #expect(r.switches["dock"] == false)  // the user chose before the seed: kept
        #expect(r.switches["finder"] == false)
        // A second run changes nothing.
        r.switches["shelf"] = false
        #expect(!r.seedFromVorssaint("shelf"))
        #expect(r.switches["shelf"] == false)
    }

    @Test func seedTurnsOnAnUntouchedDisabledDefault() {
        let b = TestDefaults.make(); defer { b.cleanup() }
        let descriptors = [FeatureDescriptor(id: "x", title: "Xylo", summary: "", systemImage: "circle",
                                             category: .tools, enabledByDefault: false)]
        let r = FeatureRegistry(descriptors: descriptors, defaults: b.defaults)
        #expect(r.switches["x"] == false)
        r.seedFromVorssaint(["xylo"])
        #expect(r.switches["x"] == true)
        #expect(FeatureRegistry(descriptors: descriptors, defaults: b.defaults).switches["x"] == true)
    }

    @Test func missingKeyStillMarksTheSeedDone() {
        let b = TestDefaults.make(); defer { b.cleanup() }
        let r = FeatureRegistry(descriptors: ShellDescriptors.all, defaults: b.defaults)
        #expect(r.seedFromVorssaint(nil))
        #expect(!r.seedFromVorssaint("dock"))
    }
}
