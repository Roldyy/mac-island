import Foundation
import Testing
@testable import ShelfFeature

@Suite struct LegacyShelfTests {
    @Test func realWorldEmptyListIsEmpty() {
        #expect(LegacyShelfImporter.parse(Data("[]".utf8)).isEmpty)
        #expect(LegacyShelfImporter.parse(Data("garbage".utf8)).isEmpty)
        #expect(LegacyShelfImporter.parse(Data()).isEmpty)
    }

    @Test func jsonStringsAndDictionaries() throws {
        let dir = makeTempDir()
        let a = makeFile("a.txt", in: dir)
        let b = makeFile("b.txt", in: dir)
        let c = makeFile("c.txt", in: dir)
        let gone = dir.appendingPathComponent("gone.txt")
        let json: [Any] = [
            a.path,
            ["path": b.path],
            ["url": c.absoluteString],
            ["path": gone.path],
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let items = LegacyShelfImporter.parse(data)
        #expect(items.map { URL(fileURLWithPath: $0.path).lastPathComponent } == ["a.txt", "b.txt", "c.txt"])
    }

    @Test func plistWithBadBookmarkFallsBackToPath() throws {
        let dir = makeTempDir()
        let a = makeFile("a.txt", in: dir)
        let plist: [Any] = [["path": a.path, "bookmark": Data([1, 2, 3])]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        let items = LegacyShelfImporter.parse(data)
        #expect(items.count == 1)
        #expect(items[0].bookmark == nil)
        #expect(items[0].path == a.standardizedFileURL.path)
    }

    @Test func bookmarkOnlyEntryResolvesPath() throws {
        let dir = makeTempDir()
        let a = makeFile("a.txt", in: dir)
        let plist: [Any] = [["bookmarkData": try a.bookmarkData()]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let items = LegacyShelfImporter.parse(data)
        #expect(items.count == 1)
        #expect(URL(fileURLWithPath: items[0].path).lastPathComponent == "a.txt")
    }

    @Test func dedupesAndNeverCrashesOnOddShapes() throws {
        let dir = makeTempDir()
        let a = makeFile("a.txt", in: dir)
        let json: [Any] = [a.path, a.path, 42, NSNull(), ["nothing": 1], [] as [Any]]
        let items = LegacyShelfImporter.parse(try JSONSerialization.data(withJSONObject: json))
        #expect(items.count == 1)
    }

    @Test func importsOnlyWhenOwnFileMissing() throws {
        let dir = makeTempDir()
        let a = makeFile("a.txt", in: dir)
        let legacy = try JSONSerialization.data(withJSONObject: [a.path])
        let t = TempDefaults()
        t.defaults.set(legacy, forKey: "shelfItems")
        let store = ShelfStore(directory: makeTempDir())
        let first = ShelfSettings(defaults: t.defaults).loadItems(store: store)
        #expect(first.count == 1)
        #expect(store.fileExists)
        // the user empties the shelf: the legacy value must not come back
        try store.save([])
        #expect(ShelfSettings(defaults: t.defaults).loadItems(store: store).isEmpty)
    }
}
