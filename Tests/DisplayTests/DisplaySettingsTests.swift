import Foundation
import Testing
@testable import DisplayFeature

@Suite final class DisplaySettingsTests {
    private var made: [TempDefaults] = []
    func settings() -> (DisplaySettings, UserDefaults) {
        let t = TempDefaults()
        made.append(t)
        return (DisplaySettings(defaults: t.defaults), t.defaults)
    }

    @Test func defaultsWhenNothingIsStored() {
        let (s, _) = settings()
        #expect(s.brightnessControlEnabled == true)
        #expect(s.autoQuitEnabled == false)
        #expect(s.autoQuitDelayMinutes == 30)
        #expect(s.autoQuitDryRun == true)
        #expect(s.autoQuitExcludedBundleIDs.isEmpty)
    }

    @Test func migratedKeysAreRead() {
        let (s, d) = settings()
        d.set(true, forKey: "autoQuitEnabled")
        d.set(false, forKey: "brightnessControlEnabled")
        #expect(s.autoQuitEnabled == true)
        #expect(s.brightnessControlEnabled == false)
    }

    @Test func delayIsClamped() {
        let (s, d) = settings()
        d.set(0, forKey: DisplaySettings.delayKey)
        #expect(s.autoQuitDelayMinutes == 1)
        d.set(100_000, forKey: DisplaySettings.delayKey)
        #expect(s.autoQuitDelayMinutes == DisplaySettings.maxDelayMinutes)
    }

    @Test func writesRoundTripUnderTheOldKeyNames() {
        var (s, d) = settings()
        s.autoQuitEnabled = true
        s.autoQuitDelayMinutes = 45
        s.autoQuitDryRun = false
        s.autoQuitExcludedBundleIDs = ["b.id", "a.id"]
        #expect(d.bool(forKey: "autoQuitEnabled") == true)
        #expect(s.autoQuitDelayMinutes == 45)
        #expect(s.autoQuitDryRun == false)
        #expect(d.stringArray(forKey: DisplaySettings.excludedKey) == ["a.id", "b.id"])
    }
}
