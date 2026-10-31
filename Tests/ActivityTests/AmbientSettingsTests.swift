import Foundation
import IslandTestSupport
import Testing
@testable import IslandKit

@Suite struct AmbientSettingsTests {
    // MARK: Keys

    @Test func everyKeyStartsWithNotchIdle() {
        for key in ClosedIslandKeys.all { #expect(key.hasPrefix("notchIdle"), "\(key)") }
    }

    @Test func oneSwitchPerUserChoiceAndTheyAreDistinct() {
        let keys = AmbientChannel.userChoices.map(ClosedIslandKeys.show)
        #expect(Set(keys).count == AmbientChannel.userChoices.count)
    }

    // MARK: Migration of notchIdleContent

    @Test func noOldValueIsAFreshStartWithEverythingOn() {
        let s = ClosedIslandSettings.migrated(legacyContent: nil)
        #expect(s == .standard)
        #expect(s.enabled == Set(AmbientChannel.userChoices))
    }

    @Test func agentsKeepsTheLimitsAndAddsTheNewIndicators() {
        #expect(ClosedIslandSettings.migrated(legacyContent: "agents") == .standard)
    }

    @Test func noneKeepsNothingAtRestButTheLiveIndicators() {
        let s = ClosedIslandSettings.migrated(legacyContent: "none")
        #expect(!s.isEnabled(AmbientChannel.limits))
        #expect(!s.isEnabled(AmbientChannel.battery))
        #expect(!s.isEnabled(AmbientChannel.keepAwake))
        #expect(s.isEnabled(AmbientChannel.claude))
        #expect(s.isEnabled(AmbientChannel.music))
    }

    @Test func batteryPutsTheBatteryFirst() {
        let s = ClosedIslandSettings.migrated(legacyContent: "battery")
        #expect(s.orderedChannels.first == AmbientChannel.battery)
        #expect(s.isEnabled(AmbientChannel.battery))
        #expect(!s.isEnabled(AmbientChannel.limits))
    }

    @Test func musicPutsTheMusicFirst() {
        let s = ClosedIslandSettings.migrated(legacyContent: "music")
        #expect(s.orderedChannels.first == AmbientChannel.music)
        #expect(!s.isEnabled(AmbientChannel.limits))
    }

    @Test func anUnknownOldValueFallsBackToTheDefaults() {
        #expect(ClosedIslandSettings.migrated(legacyContent: "something-new") == .standard)
    }

    @Test func loadingMigratesOnceWritesEveryKeyAndLeavesTheOldKeyAlone() {
        let (defaults, cleanup) = TestDefaults.make()
        defer { cleanup() }
        defaults.set("none", forKey: ClosedIslandKeys.legacyContent)
        let first = ClosedIslandSettings.load(from: defaults)
        #expect(!first.isEnabled(AmbientChannel.battery))
        #expect(defaults.bool(forKey: ClosedIslandKeys.migrated))
        #expect(defaults.bool(forKey: ClosedIslandKeys.show(AmbientChannel.battery)) == false)
        #expect(defaults.bool(forKey: ClosedIslandKeys.show(AmbientChannel.claude)))
        #expect(defaults.string(forKey: ClosedIslandKeys.legacyContent) == "none")  // the Agents lane still reads it

        // The user changes their mind in Settings; a later launch must not migrate again.
        defaults.set(true, forKey: ClosedIslandKeys.show(AmbientChannel.battery))
        defaults.set("agents", forKey: ClosedIslandKeys.legacyContent)
        #expect(ClosedIslandSettings.load(from: defaults).isEnabled(AmbientChannel.battery))
    }

    // MARK: Persistence

    @Test func readFallsBackToDefaultsForMissingKeys() {
        let (defaults, cleanup) = TestDefaults.make()
        defer { cleanup() }
        let s = ClosedIslandSettings.read(from: defaults)
        #expect(s == .standard)
        #expect(defaults.object(forKey: ClosedIslandKeys.rotates) == nil)  // a pure read writes nothing
    }

    @Test func writeThenReadRoundTrips() {
        let (defaults, cleanup) = TestDefaults.make()
        defer { cleanup() }
        let s = ClosedIslandSettings(
            enabled: [AmbientChannel.battery, AmbientChannel.music],
            order: [AmbientChannel.music, AmbientChannel.battery], rotates: false, maxPerWing: 1)
        s.write(to: defaults)
        #expect(ClosedIslandSettings.read(from: defaults) == s)
    }

    @Test func aStoredPerWingOutOfRangeIsClamped() {
        let (defaults, cleanup) = TestDefaults.make()
        defer { cleanup() }
        defaults.set(7, forKey: ClosedIslandKeys.perWing)
        #expect(ClosedIslandSettings.read(from: defaults).maxPerWing == 2)
        defaults.set(-3, forKey: ClosedIslandKeys.perWing)
        #expect(ClosedIslandSettings.read(from: defaults).maxPerWing == 1)
    }

    @Test func orderedChannelsAreCompleteWithoutDuplicatesWhateverIsStored() {
        let s = ClosedIslandSettings(order: ["ghost", AmbientChannel.music, AmbientChannel.music, AmbientChannel.battery])
        #expect(s.orderedChannels == [AmbientChannel.music, AmbientChannel.battery, AmbientChannel.limits,
                                      AmbientChannel.claude, AmbientChannel.keepAwake])
    }

    // MARK: Preferences (the Settings-side binding)

    @MainActor @Test func preferencesPersistEachChange() {
        let (defaults, cleanup) = TestDefaults.make()
        defer { cleanup() }
        let prefs = ClosedIslandPreferences(defaults: defaults)
        prefs.setEnabled(AmbientChannel.battery, false)
        prefs.setRotates(false)
        prefs.setMaxPerWing(1)
        prefs.move(AmbientChannel.keepAwake, by: -4)
        let stored = ClosedIslandSettings.read(from: defaults)
        #expect(!stored.isEnabled(AmbientChannel.battery))
        #expect(!stored.rotates)
        #expect(stored.maxPerWing == 1)
        #expect(stored.orderedChannels.first == AmbientChannel.keepAwake)
        #expect(prefs.settings == stored)
    }

    @MainActor @Test func preferencesIgnoreUnknownChannelsAndOutOfRangeMoves() {
        let (defaults, cleanup) = TestDefaults.make()
        defer { cleanup() }
        let prefs = ClosedIslandPreferences(defaults: defaults)
        let before = prefs.settings
        prefs.setEnabled("alert", false)
        prefs.setEnabled("nonsense", true)
        prefs.move("nonsense", by: 1)
        prefs.move(AmbientChannel.limits, by: -3)  // already first
        #expect(prefs.settings == before)
    }

    @MainActor @Test func preferencesFollowAToggleWrittenDirectlyToTheDefaults() {
        let (defaults, cleanup) = TestDefaults.make()
        defer { cleanup() }
        let prefs = ClosedIslandPreferences(defaults: defaults)
        #expect(prefs.settings.isEnabled(AmbientChannel.battery))
        // What a Settings toggle bound to the key does.
        defaults.set(false, forKey: ClosedIslandKeys.show(AmbientChannel.battery))
        prefs.reload()
        #expect(!prefs.settings.isEnabled(AmbientChannel.battery))
    }

    @MainActor @Test func rowsListEveryChoiceInTheUsersOrderWithTheirState() {
        let (defaults, cleanup) = TestDefaults.make()
        defer { cleanup() }
        let prefs = ClosedIslandPreferences(defaults: defaults)
        prefs.setEnabled(AmbientChannel.music, false)
        let rows = prefs.rows
        #expect(rows.map(\.channel) == prefs.settings.orderedChannels)
        #expect(rows.count == AmbientChannel.userChoices.count)
        #expect(rows.first { $0.channel == AmbientChannel.music }?.isOn == false)
        #expect(rows.allSatisfy { !$0.title.isEmpty && !$0.hint.isEmpty })
    }
}
