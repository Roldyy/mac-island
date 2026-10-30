import Foundation
import Testing
@testable import ShelfFeature

@Suite struct ShelfStoreTests {
    @Test func roundTripAndPermissions() throws {
        let dir = makeTempDir().appendingPathComponent("Data", isDirectory: true)
        let store = ShelfStore(directory: dir)
        let items = [ShelfItem(path: "/tmp/a", bookmark: Data([1, 2]), addedAt: Date(timeIntervalSince1970: 10))]
        try store.save(items)
        #expect(store.load() == items)
        #expect(store.fileURL.lastPathComponent == "Shelf.json")
        #expect(posix(store.fileURL) == 0o600)
        #expect(posix(dir) == 0o700)
    }

    @Test func missingOrCorruptFileLoadsEmpty() throws {
        let dir = makeTempDir()
        let store = ShelfStore(directory: dir)
        #expect(store.load().isEmpty)
        #expect(!store.fileExists)
        try Data("not json".utf8).write(to: store.fileURL)
        #expect(store.load().isEmpty)
    }

    @Test func addDedupesByStandardizedPathAndSkipsBookmarkForSymlinks() throws {
        let dir = makeTempDir()
        let file = makeFile("a.txt", in: dir)
        let alias = dir.appendingPathComponent("sub/../a.txt")
        let link = dir.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        var seen: [String] = []
        let out = ShelfItems.add([file, alias, link], to: [], now: Date(timeIntervalSince1970: 5)) { url in
            seen.append(url.lastPathComponent)
            return Data([9])
        }
        #expect(out.count == 2)
        #expect(out[0].path == file.standardizedFileURL.path)
        #expect(out[0].bookmark == Data([9]))
        #expect(out[1].path == link.standardizedFileURL.path)
        #expect(out[1].bookmark == nil)
        #expect(seen == ["a.txt"])
        // re-adding changes nothing
        #expect(ShelfItems.add([file], to: out, now: .now) { _ in nil } == out)
    }

    @Test func removeOneAndClear() {
        let a = ShelfItem(path: "/a", bookmark: nil, addedAt: .now)
        let b = ShelfItem(path: "/b", bookmark: nil, addedAt: .now)
        #expect(ShelfItems.remove(a.id, from: [a, b]) == [b])
        #expect(ShelfItems.remove(UUID(), from: [a, b]) == [a, b])
    }

    @Test func availabilityNeverCrashesAndFollowsNoLinks() throws {
        let dir = makeTempDir()
        let file = makeFile("a.txt", in: dir)
        let item = ShelfItem(path: file.path, bookmark: nil, addedAt: .now)
        #expect(item.availability == .available)
        try FileManager.default.removeItem(at: file)
        #expect(item.availability == .missing)
        #expect(item.resolvedURL() == nil)
        #expect(ShelfItem(path: "", bookmark: nil, addedAt: .now).availability == .missing)
    }

    @Test func bookmarkFollowsRenamedFile() throws {
        let dir = makeTempDir()
        let file = makeFile("a.txt", in: dir)
        let bookmark = try file.bookmarkData()
        let item = ShelfItem(path: file.path, bookmark: bookmark, addedAt: .now)
        let moved = dir.appendingPathComponent("b.txt")
        try FileManager.default.moveItem(at: file, to: moved)
        #expect(item.resolvedURL()?.lastPathComponent == "b.txt")
    }

    @Test func dropDecoderReadsFileURLData() {
        let url = URL(fileURLWithPath: "/tmp/x y.txt")
        #expect(ShelfDropDecoder.fileURL(from: url.dataRepresentation as NSData) == url)
        #expect(ShelfDropDecoder.fileURL(from: url as NSURL) == url)
        #expect(ShelfDropDecoder.fileURL(from: Data("https://example.com".utf8) as NSData) == nil)
        #expect(ShelfDropDecoder.fileURL(from: nil) == nil)
    }
}
