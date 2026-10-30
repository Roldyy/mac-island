import Foundation
import Testing
@testable import AudioFeature

@Suite struct AudioSettingsTests {
    @Test func positionsAreReadAsIsWhenFlagged() {
        let d = makeDefaults()
        d.set(["com.example.a": 0.5, "com.example.b": 0.0], forKey: "appVolumes")
        d.set(true, forKey: "appVolumesArePositions")
        let s = AudioSettings(defaults: d)
        #expect(s.appPositions == ["com.example.a": 0.5, "com.example.b": 0.0])
    }

    @Test func linearGainsAreConvertedToPositionsWhenNotFlagged() {
        let d = makeDefaults()
        d.set(["com.example.a": 0.25], forKey: "appVolumes")
        let s = AudioSettings(defaults: d)
        #expect(abs((s.appPositions["com.example.a"] ?? -1) - 0.5) < 1e-9)
    }

    @Test func valuesAreClampedAndNonNumbersDropped() {
        let d = makeDefaults()
        d.set(["a": 5.0, "b": -2.0, "c": "loud"] as [String: Any], forKey: "appVolumes")
        d.set(true, forKey: "appVolumesArePositions")
        let s = AudioSettings(defaults: d)
        #expect(s.appPositions == ["a": 1.0, "b": 0.0])
    }

    @Test func unknownShapeStartsEmpty() {
        let d = makeDefaults()
        d.set(["x", "y"], forKey: "appVolumes")
        d.set("nope", forKey: "audioPriorityOutputUIDs")
        d.set(42, forKey: "audioPriorityInputUIDs")
        d.set([1, 2], forKey: "audioPriorityDeviceNames")
        let s = AudioSettings(defaults: d)
        #expect(s.appPositions.isEmpty)
        #expect(s.priority(for: .output).isEmpty)
        #expect(s.priority(for: .input).isEmpty)
        #expect(s.deviceNames.isEmpty)
    }

    @Test func priorityDropsNonStringsAndDuplicates() {
        let d = makeDefaults()
        d.set(["a", 3, "b", "a", ""] as [Any], forKey: "audioPriorityOutputUIDs")
        let s = AudioSettings(defaults: d)
        #expect(s.priority(for: .output) == ["a", "b"])
    }

    @Test func saveRoundTripsAndFlagsPositions() {
        let d = makeDefaults()
        let s = AudioSettings(defaults: d)
        s.setPosition(0.3, for: "com.example.a")
        s.setPriority(["u1", "u2"], for: .input)
        s.setDeviceName("friendly", for: "u1")
        s.setMuted(true, for: "com.example.a")
        #expect(d.bool(forKey: "appVolumesArePositions") == true)
        let again = AudioSettings(defaults: d)
        #expect(again.appPositions["com.example.a"] == 0.3)
        #expect(again.priority(for: .input) == ["u1", "u2"])
        #expect(again.deviceNames["u1"] == "friendly")
        #expect(again.mutedApps == ["com.example.a"])
        s.setMuted(false, for: "com.example.a")
        #expect(AudioSettings(defaults: d).mutedApps.isEmpty)
    }
}
