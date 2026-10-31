import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import ShellKit

@MainActor
@Suite struct VorssaintHubSeedTests {
    let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))

    @Test func parsesEveryPlausibleShape() throws {
        #expect(VorssaintHubSeed.tokens(in: "superKey, dock;clipboard") == ["superKey", "dock", "clipboard"])
        #expect(VorssaintHubSeed.tokens(in: ["a", "b"]) == ["a", "b"])
        #expect(VorssaintHubSeed.tokens(in: ["a": true, "b": false]) == ["a"])
        // Only a real Boolean true keeps a feature, not a string, a number or a missing flag.
        #expect(VorssaintHubSeed.tokens(in: ["a": true, "b": "NO", "c": 2, "d": 1, "e": "YES", "f": NSNull()]) == ["a"])
        #expect(VorssaintHubSeed.tokens(in: ["a": NSNumber(value: true), "b": NSNumber(value: false)]) == ["a"])
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

    @Test func seedKeepsNamedFeaturesAndSwitchesOffTheUntouchedRest() {
        let b = TestDefaults.make(); defer { b.cleanup() }
        let r = FeatureRegistry(descriptors: ShellDescriptors.all, defaults: b.defaults, crashMarker: marker)
        #expect(r.seedFromVorssaint("dock mixer"))
        #expect(r.switches["dock"] == true)
        #expect(r.switches["audio"] == true)  // alias of "mixer"
        let others = ShellDescriptors.all.map(\.id).filter { $0 != "dock" && $0 != "audio" }
        #expect(others.allSatisfy { r.switches[$0] == false })
        // Persisted: a fresh registry reads the seeded switches.
        let fresh = FeatureRegistry(descriptors: ShellDescriptors.all, defaults: b.defaults, crashMarker: marker)
        #expect(fresh.switches["dock"] == true && fresh.switches["terminal"] == false)
    }

    @Test func seedNeverOverridesAChoiceTheUserAlreadyMade() {
        let b = TestDefaults.make(); defer { b.cleanup() }
        // Dock is off by user choice, shelf was switched on by the user, finder is untouched.
        b.defaults.set(false, forKey: FeatureRegistry.Keys.enabled("dock"))
        b.defaults.set(true, forKey: FeatureRegistry.Keys.enabled("shelf"))
        let r = FeatureRegistry(descriptors: ShellDescriptors.all, defaults: b.defaults, crashMarker: marker)
        #expect(r.seedFromVorssaint("dock finder"))
        #expect(r.switches["dock"] == false)  // named, but the user chose first
        #expect(r.switches["shelf"] == true)  // not named, but the user chose first
        #expect(r.switches["finder"] == true)
        #expect(r.switches["monitor"] == false)
        // A second run changes nothing.
        r.switches["monitor"] = true
        #expect(!r.seedFromVorssaint("shelf"))
        #expect(r.switches["monitor"] == true)
    }

    @Test func aValueNamingNoKnownFeatureChangesNothing() {
        for raw: Any? in [nil, "", "superKey whatever", ["x"], ["dock": "NO"], ["dock": 2], 42] {
            let b = TestDefaults.make(); defer { b.cleanup() }
            let r = FeatureRegistry(descriptors: ShellDescriptors.all, defaults: b.defaults, crashMarker: marker)
            let before = r.switches
            #expect(r.seedFromVorssaint(raw))
            #expect(r.switches == before, "\(String(describing: raw))")
            #expect(!r.seedFromVorssaint("dock"), "still marked done")
        }
    }

    @Test func seedTurnsOnAnUntouchedDisabledDefault() {
        let b = TestDefaults.make(); defer { b.cleanup() }
        let descriptors = [FeatureDescriptor(id: "x", title: "Xylo", summary: "", systemImage: "circle",
                                             category: .tools, enabledByDefault: false)]
        let r = FeatureRegistry(descriptors: descriptors, defaults: b.defaults, crashMarker: marker)
        #expect(r.switches["x"] == false)
        r.seedFromVorssaint(["xylo"])
        #expect(r.switches["x"] == true)
        #expect(FeatureRegistry(descriptors: descriptors, defaults: b.defaults, crashMarker: marker).switches["x"] == true)
    }

    @Test func missingKeyStillMarksTheSeedDone() {
        let b = TestDefaults.make(); defer { b.cleanup() }
        let r = FeatureRegistry(descriptors: ShellDescriptors.all, defaults: b.defaults, crashMarker: marker)
        #expect(r.seedFromVorssaint(nil))
        #expect(!r.seedFromVorssaint("dock"))
    }
}
