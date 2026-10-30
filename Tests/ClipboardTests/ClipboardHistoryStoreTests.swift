import Foundation
import Testing
@testable import ClipboardFeature

@Suite struct ClipboardHistoryStoreTests {
    func makeStore(limit: Int = 50, dir: URL = makeTempDir(), clock: @escaping () -> Date = Date.init)
        -> (ClipboardHistoryStore, URL) {
        (ClipboardHistoryStore(directory: dir, limit: limit, now: clock), dir)
    }

    @Test func newestFirst() {
        let (s, _) = makeStore()
        s.addText("one", source: nil)
        s.addText("two", source: nil)
        #expect(s.entries.map(\.text) == ["two", "one"])
    }

    @Test func dedupesOnlyConsecutive() {
        let (s, _) = makeStore()
        #expect(s.addText("a", source: nil))
        #expect(!s.addText("a", source: nil))
        #expect(s.addText("b", source: nil))
        #expect(s.addText("a", source: nil))
        #expect(s.entries.count == 3)
    }

    @Test func ignoresEmptyText() {
        let (s, _) = makeStore()
        #expect(!s.addText("", source: nil))
        #expect(!s.addText("  \n", source: nil))
        #expect(s.entries.isEmpty)
    }

    @Test func limitTrimsOldestUnpinned() {
        let (s, _) = makeStore(limit: 3)
        for t in ["1", "2", "3"] { s.addText(t, source: nil) }
        s.togglePin(id: s.entries.last!.id)   // pin "1"
        s.addText("4", source: nil)
        s.addText("5", source: nil)
        #expect(s.entries.map(\.text) == ["5", "4", "3", "1"])   // limit counts unpinned only
        #expect(s.entries.contains { $0.text == "1" && $0.pinned })
        #expect(!s.entries.contains { $0.text == "2" })
    }

    @Test func limitClampedToAtLeastOne() {
        let (s, _) = makeStore(limit: 0)
        s.addText("a", source: nil)
        s.addText("b", source: nil)
        #expect(s.entries.map(\.text) == ["b"])
    }

    @Test func removeAndClear() {
        let (s, _) = makeStore()
        s.addText("a", source: nil)
        s.addText("b", source: nil)
        s.remove(id: s.entries[0].id)
        #expect(s.entries.map(\.text) == ["a"])
        s.addText("c", source: nil)
        s.togglePin(id: s.entries[0].id)
        s.clearAll(keepPinned: true)
        #expect(s.entries.map(\.text) == ["c"])
        s.clearAll(keepPinned: false)
        #expect(s.entries.isEmpty)
    }

    @Test func imagesStoredAndDeletedWithEntry() throws {
        let (s, dir) = makeStore()
        let bytes = Data([1, 2, 3, 4])
        #expect(s.addImage(png: bytes, width: 2, height: 3, source: "x.y"))
        #expect(!s.addImage(png: bytes, width: 2, height: 3, source: "x.y"))   // consecutive duplicate
        let e = try #require(s.entries.first)
        let url = try #require(s.imageURL(for: e))
        #expect(try Data(contentsOf: url) == bytes)
        #expect(url.deletingLastPathComponent().lastPathComponent == "ClipboardImages")
        #expect(posix(url) == 0o600)
        #expect(posix(dir.appendingPathComponent("ClipboardImages")) == 0o700)
        s.remove(id: e.id)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func persistsAndReloads() throws {
        let dir = makeTempDir()
        let a = ClipboardHistoryStore(directory: dir, limit: 50)
        a.addText("hello", source: "com.example.app")
        a.addImage(png: Data([9, 9]), width: 4, height: 5, source: nil)
        a.addFiles(["/tmp/a.txt", "/tmp/b.txt"], source: nil)
        a.togglePin(id: a.entries[2].id)
        let b = ClipboardHistoryStore(directory: dir, limit: 50)
        b.load()
        #expect(b.entries == a.entries)
        let file = dir.appendingPathComponent("ClipboardHistory.json")
        #expect(posix(file) == 0o600)
    }

    @Test func createsPrivateDirectory() {
        let parent = makeTempDir()
        let dir = parent.appendingPathComponent("Data")
        let s = ClipboardHistoryStore(directory: dir, limit: 5)
        s.addText("x", source: nil)
        #expect(posix(dir) == 0o700)
    }

    // The migrated file observed on the real machine: array of objects with
    // id, kind (text|image|files), text, filePaths, sourceBundleID, copiedAt (seconds since 2001),
    // and for images imageFile, imageHash, imageWidth, imageHeight. Synthetic values only.
    @Test func readsLegacyShapeTolerantly() throws {
        let dir = makeTempDir()
        let json = """
        [
          {"id":"AAAAAAAA-0000-0000-0000-000000000001","kind":"text","text":"synthetic one",
           "filePaths":[],"sourceBundleID":"com.example.a","copiedAt":814980691.5,"futureKey":{"x":1}},
          {"id":"AAAAAAAA-0000-0000-0000-000000000002","kind":"image","text":"","filePaths":[],
           "sourceBundleID":"com.example.b","copiedAt":814980600.0,
           "imageFile":"legacy-name.png","imageHash":"abc","imageWidth":10,"imageHeight":20},
          {"id":"AAAAAAAA-0000-0000-0000-000000000003","kind":"files","text":"two files",
           "filePaths":["/tmp/x","/tmp/y"],"sourceBundleID":"com.example.c","copiedAt":814980500.0},
          {"id":"bad-kind","kind":"hologram","text":"x","copiedAt":1.0},
          {"id":"bad-image","kind":"image","text":"","copiedAt":1.0,"imageFile":"../escape.png"},
          {"kind":"text","copiedAt":"not a number"},
          "just a string",
          42
        ]
        """
        try json.write(to: dir.appendingPathComponent("ClipboardHistory.json"), atomically: true, encoding: .utf8)
        let s = ClipboardHistoryStore(directory: dir, limit: 50)
        s.load()
        #expect(s.entries.count == 3)
        #expect(s.entries[0].text == "synthetic one")
        #expect(s.entries[0].copiedAt == Date(timeIntervalSinceReferenceDate: 814980691.5))
        #expect(s.entries[0].pinned == false)
        #expect(s.entries[1].kind == .image && s.entries[1].imageFile == "legacy-name.png")
        #expect(s.entries[1].imageWidth == 10)
        #expect(s.entries[2].kind == .files && s.entries[2].filePaths == ["/tmp/x", "/tmp/y"])
    }

    @Test func garbageFileLoadsEmpty() throws {
        let dir = makeTempDir()
        try "not json at all".write(to: dir.appendingPathComponent("ClipboardHistory.json"), atomically: true, encoding: .utf8)
        let s = ClipboardHistoryStore(directory: dir, limit: 5)
        s.load()
        #expect(s.entries.isEmpty)
    }

    @Test func searchAndDisplayOrder() {
        let (s, _) = makeStore()
        s.addText("Alpha note", source: nil)
        s.addText("beta", source: nil)
        s.addText("ALPHA two", source: nil)
        s.togglePin(id: s.entries.last!.id)   // pin "Alpha note"
        #expect(s.displayEntries(matching: "").map(\.text) == ["Alpha note", "ALPHA two", "beta"])
        #expect(s.displayEntries(matching: "alpha").map(\.text) == ["Alpha note", "ALPHA two"])
    }

    @Test func moveToFrontRefreshesDate() {
        var t = Date(timeIntervalSinceReferenceDate: 1000)
        let (s, _) = makeStore(clock: { t })
        s.addText("a", source: nil)
        t = t.addingTimeInterval(60)
        s.addText("b", source: nil)
        t = t.addingTimeInterval(60)
        s.moveToFront(id: s.entries[1].id)
        #expect(s.entries.map(\.text) == ["a", "b"])
        #expect(s.entries[0].copiedAt == t)
    }
}
