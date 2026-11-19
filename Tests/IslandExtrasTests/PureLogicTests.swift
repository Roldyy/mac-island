import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import IslandExtrasFeature
@testable import ShellKit

// MARK: - Notes

@Suite struct NotesStoreTests {
    private func tempDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mis-notes-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func aMissingFileLoadsAsEmptyText() {
        let store = NotesStore(directory: tempDirectory())
        #expect(store.load() == "")
    }

    @Test func aNoteRoundTripsAndTheFileIsOwnerOnly() throws {
        let dir = tempDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = NotesStore(directory: dir)
        #expect(store.save("Appeler le client\nÀ 14 h"))
        #expect(NotesStore(directory: dir).load() == "Appeler le client\nÀ 14 h")
        let attributes = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(NotesStore.fileName).path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
    }

    @Test func aCorruptFileLoadsAsEmptyAndTheNextSaveHealsIt() throws {
        let dir = tempDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("pas du json".utf8).write(to: dir.appendingPathComponent(NotesStore.fileName))
        let store = NotesStore(directory: dir)
        #expect(store.load() == "")
        #expect(store.save("neuf") && store.load() == "neuf")
    }

    @Test func aNoteIsCutAtTheCap() {
        let dir = tempDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = NotesStore(directory: dir)
        let long = String(repeating: "a", count: NotesStore.maxLength + 500)
        #expect(store.save(long))
        #expect(store.load().count == NotesStore.maxLength)
    }

    @Test func withoutADirectoryNothingIsSavedAndNothingCrashes() {
        let store = NotesStore(directory: nil)
        #expect(!store.save("x") && store.load() == "")
    }
}

// MARK: - Recent colours

@Suite struct RecentColoursTests {
    @Test func aColourIsWrittenAsUppercaseHex() {
        #expect(RecentColours.hex(red: 1, green: 0, blue: 0) == "#FF0000")
        #expect(RecentColours.hex(red: 0.2, green: 0.4, blue: 0.6) == "#336699")
        #expect(RecentColours.hex(red: 2, green: -1, blue: 0.5) == "#FF0080", "out of range components are clamped")
    }

    @Test func normalisingAcceptsHexAndRejectsTheRest() {
        #expect(RecentColours.normalised("#abc123") == "#ABC123")
        #expect(RecentColours.normalised("abc123") == "#ABC123")
        #expect(RecentColours.normalised("#ABC") == nil)
        #expect(RecentColours.normalised("#GGGGGG") == nil)
        #expect(RecentColours.normalised("") == nil)
    }

    @Test func theNewestComesFirstAndADuplicateMovesToTheFront() {
        var recent = RecentColours()
        recent.add("#111111"); recent.add("#222222"); recent.add("#333333")
        #expect(recent.hexes == ["#333333", "#222222", "#111111"])
        recent.add("#111111")
        #expect(recent.hexes == ["#111111", "#333333", "#222222"])
        recent.add("#111111")
        #expect(recent.hexes.count == 3)
    }

    @Test func theListIsCapped() {
        var recent = RecentColours()
        for n in 0..<(RecentColours.capacity + 5) { recent.add(String(format: "#%06X", n + 1)) }
        #expect(recent.hexes.count == RecentColours.capacity)
        #expect(recent.hexes.first == String(format: "#%06X", RecentColours.capacity + 5))
    }

    @Test func anInvalidValueIsIgnored() {
        var recent = RecentColours()
        recent.add("rouge")
        #expect(recent.hexes.isEmpty)
    }

    @Test func itPersistsThroughDefaultsAndDropsJunk() {
        let bench = TestDefaults.make(); defer { bench.cleanup() }
        var recent = RecentColours()
        recent.add("#AA0000"); recent.add("#00BB00")
        recent.save(to: bench.defaults)
        #expect(RecentColours.load(from: bench.defaults).hexes == ["#00BB00", "#AA0000"])
        bench.defaults.set(["#123456", "nope", 7] as [Any], forKey: RecentColours.defaultsKey)
        #expect(RecentColours.load(from: bench.defaults).hexes == ["#123456"])
    }
}

// MARK: - Battery display

@Suite struct BatteryDisplayTests {
    @Test func onBatteryItShowsThePercentAndTheTimeLeft() {
        let d = BatteryDisplay(reading: BatteryReading(percent: 82, isPluggedIn: false, isCharging: false, minutes: 200), health: nil)
        #expect(d.percentText == "82 %")
        #expect(d.stateText == "Sur batterie")
        #expect(d.remainingText == "3 h 20 min restantes")
        #expect(d.healthText == nil)
    }

    @Test func chargingShowsTheTimeToFull() {
        let d = BatteryDisplay(reading: BatteryReading(percent: 40, isPluggedIn: true, isCharging: true, minutes: 45), health: nil)
        #expect(d.stateText == "En charge")
        #expect(d.remainingText == "Pleine dans 45 min")
    }

    @Test func pluggedAndFullIsCharged() {
        let d = BatteryDisplay(reading: BatteryReading(percent: 100, isPluggedIn: true, isCharging: false), health: nil)
        #expect(d.stateText == "Chargée" && d.remainingText == nil)
        let d2 = BatteryDisplay(reading: BatteryReading(percent: 90, isPluggedIn: true, isCharging: false), health: nil)
        #expect(d2.stateText == "Sur secteur")
    }

    @Test func withoutAnEstimateThereIsNoRemainingText() {
        let d = BatteryDisplay(reading: BatteryReading(percent: 50, isPluggedIn: false, isCharging: false, minutes: nil), health: nil)
        #expect(d.remainingText == nil)
    }

    @Test func healthIsRawMaxOverDesignAndNeedsBothValues() {
        #expect(BatteryHealth.make(rawMaxCapacity: 4500, designCapacity: 5000, cycles: 120) == BatteryHealth(percent: 90, cycles: 120))
        #expect(BatteryHealth.make(rawMaxCapacity: 5200, designCapacity: 5000, cycles: nil)?.percent == 100, "capped at 100")
        #expect(BatteryHealth.make(rawMaxCapacity: nil, designCapacity: 5000, cycles: 1) == nil)
        #expect(BatteryHealth.make(rawMaxCapacity: 4000, designCapacity: 0, cycles: 1) == nil)
    }

    @Test func healthTextNamesTheCyclesWhenKnown() {
        let reading = BatteryReading(percent: 60, isPluggedIn: false, isCharging: false)
        #expect(BatteryDisplay(reading: reading, health: BatteryHealth(percent: 91, cycles: 230)).healthText == "Santé 91 % · 230 cycles")
        #expect(BatteryDisplay(reading: reading, health: BatteryHealth(percent: 91, cycles: nil)).healthText == "Santé 91 %")
        #expect(BatteryDisplay(reading: reading, health: BatteryHealth(percent: 91, cycles: 1)).healthText == "Santé 91 % · 1 cycle")
    }
}

// MARK: - Network notice

@Suite struct NetworkTransitionFilterTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }
    private func settle(_ f: inout NetworkTransitionFilter, _ date: Date) -> NetworkTransitionFilter.Notice? { f.settle(at: date) }

    @Test func theFirstStableStateRaisesNoNotice() {
        var filter = NetworkTransitionFilter(debounce: 1)
        filter.observe(online: true, at: at(0))
        let r1 = settle(&filter, at(0.5)); #expect(r1 == nil, "still inside the debounce")
        let r2 = settle(&filter, at(1.2)); #expect(r2 == nil, "first state is the baseline, never announced")
        #expect(filter.stable == true)
        let offlineFirst = { () -> NetworkTransitionFilter.Notice? in
            var f = NetworkTransitionFilter(debounce: 1)
            f.observe(online: false, at: self.at(0))
            return f.settle(at: self.at(2))
        }()
        #expect(offlineFirst == nil)
    }

    @Test func aLossAndARestoreAreAnnouncedAfterTheDebounce() {
        var filter = NetworkTransitionFilter(debounce: 1)
        filter.observe(online: true, at: at(0)); _ = filter.settle(at: at(2))
        filter.observe(online: false, at: at(10))
        let r3 = settle(&filter, at(10.5)); #expect(r3 == nil)
        let r4 = settle(&filter, at(11.1)); #expect(r4 == .lost)
        let r5 = settle(&filter, at(12)); #expect(r5 == nil, "announced once")
        filter.observe(online: true, at: at(20))
        let r6 = settle(&filter, at(21)); #expect(r6 == .restored)
    }

    @Test func aFlapShorterThanTheDebounceIsSwallowed() {
        var filter = NetworkTransitionFilter(debounce: 1)
        filter.observe(online: true, at: at(0)); _ = filter.settle(at: at(2))
        filter.observe(online: false, at: at(10))
        filter.observe(online: true, at: at(10.4))
        let r7 = settle(&filter, at(12)); #expect(r7 == nil)
        #expect(filter.stable == true)
    }

    @Test func theDebounceRestartsWhenTheValueChangesAgain() {
        var filter = NetworkTransitionFilter(debounce: 1)
        filter.observe(online: true, at: at(0)); _ = filter.settle(at: at(2))
        filter.observe(online: false, at: at(10))
        filter.observe(online: true, at: at(10.6))
        filter.observe(online: false, at: at(10.9))
        let r8 = settle(&filter, at(11.5)); #expect(r8 == nil, "0.6 s since the last change")
        let r9 = settle(&filter, at(12)); #expect(r9 == .lost)
    }

    @Test func theNoticesAreFrenchAlertsOwnedByTheFeature() {
        let lost = NetworkNotice.activity(for: .lost)
        #expect(lost.leading?.text == "Réseau perdu" && lost.priority == .alert && lost.source == "networkNotice")
        let back = NetworkNotice.activity(for: .restored)
        #expect(back.leading?.text == "Réseau rétabli" && back.source == IslandExtrasFeature.networkNoticeID)
        #expect(lost.id == back.id, "one slot: the second notice replaces the first")
    }
}

// MARK: - Caps Lock (the pure part lives in ShellKit)

@Suite struct CapsLockEdgeDetectorTests {
    private func flip(_ d: inout CapsLockEdgeDetector, _ on: Bool) -> Bool { d.changed(to: on) }

    @Test func theFirstReadingIsAChangeThenOnlyFlips() {
        var d = CapsLockEdgeDetector()
        let c10 = flip(&d, false); #expect(c10, "first reading establishes the state")
        let c11 = flip(&d, false); #expect(!c11)
        let c12 = flip(&d, true); #expect(c12)
        let c13 = flip(&d, true); #expect(!c13)
        let c14 = flip(&d, false); #expect(c14)
    }

    @Test func theIndicatorIsAFrenchShortLabelOnItsOwnChannel() {
        let i = AmbientReadings.capsLock()
        #expect(i.channel == AmbientChannel.capsLock && i.id == AmbientReadings.capsLockID)
        #expect(i.text == "Verr. Maj" && i.isReadable)
        #expect(AmbientChannel.userChoices.contains(AmbientChannel.capsLock))
        #expect(!AmbientChannel.defaultOn.contains(AmbientChannel.capsLock), "off by default")
        #expect(AmbientChannel.title(AmbientChannel.capsLock) == "Verrouillage majuscules")
    }
}
