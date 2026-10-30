import Foundation
import Testing
@testable import CommandBarFeature

@Suite struct HabitStoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test @MainActor func recordsCountsAndPersists() throws {
        let dir = makeTempDir().appendingPathComponent("Data")
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let store = HabitStore(directory: dir)
        store.record("app:/Applications/Safari.app", now: t0)
        store.record("app:/Applications/Safari.app", now: t0)
        #expect(abs(store.weight("app:/Applications/Safari.app", now: t0) - 2) < 1e-9)
        #expect(store.weight("nope", now: t0) == 0)

        let reloaded = HabitStore(directory: dir)
        #expect(abs(reloaded.weight("app:/Applications/Safari.app", now: t0) - 2) < 1e-9)
        #expect(reloaded.lastUsed("app:/Applications/Safari.app") == t0)
    }

    @Test @MainActor func fileIsPrivateAndAtomic() throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("Data")
        let store = HabitStore(directory: dir)
        store.record("cmd:x", now: t0)
        let fm = FileManager.default
        let fileMode = try #require(fm.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? NSNumber)
        let dirMode = try #require(fm.attributesOfItem(atPath: dir.path)[.posixPermissions] as? NSNumber)
        #expect(fileMode.intValue == 0o600)
        #expect(dirMode.intValue == 0o700)
        #expect(store.fileURL.lastPathComponent == "CommandBarHabits.json")
        let leftovers = try fm.contentsOfDirectory(atPath: dir.path)
        #expect(leftovers == ["CommandBarHabits.json"])
    }

    @Test @MainActor func storesOnlyIdsCountsAndDates() throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HabitStore(directory: root)
        store.record("cmd:x", now: t0)
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any])
        #expect(Set(json.keys) == ["version", "entries"])
        let entries = try #require(json["entries"] as? [String: [String: Any]])
        #expect(Set(entries["cmd:x"]?.keys.map { $0 } ?? []) == ["count", "last"])
    }

    @Test @MainActor func countsDecayWithHalfLife() {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HabitStore(directory: root, halfLifeDays: 30)
        store.record("a", now: t0)
        store.record("a", now: t0)
        let later = t0.addingTimeInterval(30 * 86_400)
        #expect(abs(store.weight("a", now: later) - 1) < 1e-6)
        store.record("a", now: later)                              // decays 2 -> 1, then +1
        #expect(abs(store.weight("a", now: later) - 2) < 1e-6)
    }

    @Test @MainActor func negligibleEntriesArePruned() throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HabitStore(directory: root, halfLifeDays: 30)
        store.record("old", now: t0)
        store.record("new", now: t0.addingTimeInterval(86_400 * 600))
        let reloaded = HabitStore(directory: root, halfLifeDays: 30)
        #expect(reloaded.lastUsed("old") == nil)
        #expect(reloaded.lastUsed("new") != nil)
    }

    @Test @MainActor func clearRemovesFileAndMemory() {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HabitStore(directory: root)
        store.record("a", now: t0)
        store.clear()
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        #expect(store.weight("a", now: t0) == 0)
        #expect(HabitStore(directory: root).weight("a", now: t0) == 0)
    }

    @Test @MainActor func corruptFileIsIgnored() throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("not json".utf8).write(to: root.appendingPathComponent("CommandBarHabits.json"))
        let store = HabitStore(directory: root)
        #expect(store.weight("a", now: t0) == 0)
        store.record("a", now: t0)
        #expect(store.weight("a", now: t0) > 0)
    }

    @Test @MainActor func topIDsAreOrderedByWeight() {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HabitStore(directory: root)
        store.record("a", now: t0)
        store.record("b", now: t0); store.record("b", now: t0)
        #expect(store.topIDs(limit: 5, now: t0) == ["b", "a"])
        #expect(store.topIDs(limit: 1, now: t0) == ["b"])
    }
}
