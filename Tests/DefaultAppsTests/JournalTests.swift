import Foundation
import IslandTestSupport
import Testing
@testable import DefaultAppsFeature

@Suite struct JournalTests {
    let bench = TestDefaults.make()

    func entry(_ replacement: String = "r.app", changes: [JournalChange]) -> JournalEntry {
        JournalEntry(date: Date(timeIntervalSince1970: 1_800_000_000), replacementBundleID: replacement, replacementName: "R",
                     sourceName: "S", changes: changes)
    }

    @Test func theCodecRoundTripsAVersionedJson() throws {
        let journal = DefaultAppsJournal(entries: [entry(changes: [JournalChange(kind: .contentType, identifier: "public.json", previousBundleID: "a.app"),
                                                                    JournalChange(kind: .scheme, identifier: "subl", previousBundleID: nil, state: .applied)])])
        let text = try #require(JournalCodec.encode(journal))
        #expect(text.contains("\"version\":1"))
        #expect(JournalCodec.decode(text) == .journal(journal))
    }

    @Test func aNewerVersionIsReadOnlyAndGarbageIsCorrupt() {
        #expect(JournalCodec.decode("{\"version\":99,\"entries\":[]}") == .unsupportedVersion(99))
        #expect(JournalCodec.decode("not json") == .corrupt)
        #expect(JournalCodec.decode("{\"version\":1}") == .corrupt)
        #expect(JournalCodec.decode(String(repeating: "x", count: JournalCodec.maxBytes * 2 + 1)) == .corrupt)
    }

    @Test func theSizeIsCappedByDroppingTheOldestEntriesAndTheLongestLists() throws {
        let many = (0..<100).map { i in entry("r\(i)", changes: [JournalChange(kind: .contentType, identifier: "t\(i)", previousBundleID: "p")]) }
        let text = try #require(JournalCodec.encode(DefaultAppsJournal(entries: many)))
        guard case .journal(let decoded) = JournalCodec.decode(text) else { Issue.record("not decodable"); return }
        #expect(decoded.entries.count == JournalCodec.maxEntries)
        #expect(decoded.entries.last?.replacementBundleID == "r99", "the newest entries are kept")
        let fat = entry(changes: (0..<2000).map { JournalChange(kind: .contentType, identifier: "t\($0)", previousBundleID: "p") })
        guard case .journal(let capped) = JournalCodec.decode(try #require(JournalCodec.encode(DefaultAppsJournal(entries: [fat])))) else {
            Issue.record("not decodable"); return
        }
        #expect(capped.entries[0].changes.count == JournalCodec.maxChangesPerEntry)
    }

    @Test func theStoreWritesAJsonStringUnderTheDocumentedKey() throws {
        defer { bench.cleanup() }
        let store = DefaultAppsJournalStore(defaults: bench.defaults)
        let e = entry(changes: [JournalChange(kind: .contentType, identifier: "public.json", previousBundleID: "a.app")])
        #expect(store.append(e))
        #expect(DefaultAppsJournalStore.key == "defaultAppsJournal")
        #expect(bench.defaults.string(forKey: "defaultAppsJournal")?.contains("public.json") == true)
        #expect(store.entries == [e])
        #expect(store.mark(entry: e.id, key: "contentType:public.json", state: .applied))
        #expect(store.entries[0].changes[0].state == .applied)
    }

    @Test func aCorruptJournalIsKeptAsideThenReplaced() {
        defer { bench.cleanup() }
        bench.defaults.set("garbage", forKey: DefaultAppsJournalStore.key)
        let store = DefaultAppsJournalStore(defaults: bench.defaults)
        #expect(store.load() == .corrupt && store.entries.isEmpty)
        #expect(store.append(entry(changes: [JournalChange(kind: .scheme, identifier: "x", previousBundleID: nil)])))
        #expect(bench.defaults.string(forKey: DefaultAppsJournalStore.backupKey) == "garbage")
        #expect(store.entries.count == 1)
    }

    @Test func aJournalFromANewerAppIsNeverOverwritten() {
        defer { bench.cleanup() }
        let future = "{\"version\":7,\"entries\":[]}"
        bench.defaults.set(future, forKey: DefaultAppsJournalStore.key)
        let store = DefaultAppsJournalStore(defaults: bench.defaults)
        #expect(!store.append(entry(changes: [])))
        #expect(bench.defaults.string(forKey: DefaultAppsJournalStore.key) == future)
    }

    @Test func theUndoPlanKeepsTheOldestPreviousAndTheNewestReplacement() {
        let first = entry("r1", changes: [JournalChange(kind: .contentType, identifier: "A", previousBundleID: "x", state: .applied),
                                           JournalChange(kind: .contentType, identifier: "F", previousBundleID: "x", state: .failed)])
        let second = entry("r2", changes: [JournalChange(kind: .contentType, identifier: "A", previousBundleID: "r1", state: .applied),
                                            JournalChange(kind: .scheme, identifier: "s", previousBundleID: nil, state: .unverified)])
        let plan = UndoPlanner.plan(entries: [first, second])
        #expect(plan.map(\.id) == ["contentType:A", "scheme:s"], "a failed change has nothing to undo")
        #expect(plan[0].restoreTo == "x" && plan[0].expectedCurrent == "r2")
        #expect(plan[1].restoreTo == nil && plan[1].expectedCurrent == "r2")
        #expect(UndoPlanner.plan(entries: [second]).first?.restoreTo == "r1")
    }

    @Test func theChoicesStoreCapsAndReplacesPerKey() {
        defer { bench.cleanup() }
        let store = DefaultAppsChoicesStore(defaults: bench.defaults)
        store.upsert(StoredChoice(kind: .contentType, identifier: "a", bundleID: "one", explicitlyPicked: false))
        store.upsert(StoredChoice(kind: .contentType, identifier: "a", bundleID: "two", explicitlyPicked: false))
        #expect(store.choices.map(\.bundleID) == ["two"])
        for i in 0..<(DefaultAppsChoicesStore.maxChoices + 20) {
            store.upsert(StoredChoice(kind: .contentType, identifier: "t\(i)", bundleID: "b", explicitlyPicked: false))
        }
        #expect(store.choices.count == DefaultAppsChoicesStore.maxChoices)
        store.remove(keys: ["contentType:t519"])
        #expect(!store.choices.contains { $0.identifier == "t519" })
    }
}
