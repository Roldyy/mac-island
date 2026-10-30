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

    @Test func availabilityNeverCrashes() throws {
        let dir = makeTempDir()
        let file = makeFile("a.txt", in: dir)
        let item = ShelfItem(path: file.path, bookmark: nil, addedAt: .now)
        #expect(item.availability == .available)
        try FileManager.default.removeItem(at: file)
        #expect(item.availability == .missing)
        #expect(item.resolvedURL() == nil)
        #expect(ShelfItem(path: "", bookmark: nil, addedAt: .now).availability == .missing)
    }

    @Test func shelfStoresTheSymlinkItselfNeverTheTargetContents() throws {
        let dir = makeTempDir()
        let target = makeFile("target.txt", in: dir, bytes: 4096)
        let link = dir.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let items = ShelfItems.add([link], to: [], now: .now) { _ in Data([7]) }
        let item = try #require(items.first)
        #expect(item.path == link.standardizedFileURL.path)
        #expect(item.bookmark == nil)
        #expect(item.displayName == "link.txt")
        // the stored JSON carries the path only, nothing of the target
        let store = ShelfStore(directory: makeTempDir())
        try store.save(items)
        let raw = try Data(contentsOf: store.fileURL)
        #expect(raw.count < 1024)
        // removing the target leaves the link itself present (lstat), still never followed
        try FileManager.default.removeItem(at: target)
        #expect(item.availability == .available)
        #expect(ShelfFileCheck.isSymlink(item.path))
    }

    @Test func movedFileStaysAvailableThroughItsBookmark() throws {
        let dir = makeTempDir()
        let file = makeFile("a.txt", in: dir)
        let item = ShelfItem(path: file.path, bookmark: ShelfItem.makeBookmark(file), addedAt: .now)
        try FileManager.default.moveItem(at: file, to: dir.appendingPathComponent("b.txt"))
        #expect(item.availability == .available)
        let resolved = try #require(item.resolve())
        #expect(resolved.url.lastPathComponent == "b.txt")
        #expect(resolved.item.path.hasSuffix("/b.txt"))
        #expect(resolved.item.displayName == "b.txt")
        #expect(resolved.item.id == item.id)
    }

    @Test func newFileAtTheOldPathIsNeverPassedOffAsTheShelvedOne() throws {
        let dir = makeTempDir()
        let file = makeFile("a.txt", in: dir, bytes: 4)
        let item = ShelfItem(path: file.path, bookmark: ShelfItem.makeBookmark(file), addedAt: .now)
        try FileManager.default.moveItem(at: file, to: dir.appendingPathComponent("b.txt"))
        makeFile("a.txt", in: dir, bytes: 99)
        // one answer for every consumer: tile state, icon, reveal and drag
        #expect(item.resolve() == nil)
        #expect(item.resolvedURL() == nil)
        #expect(item.availability == .missing)
    }

    @Test func stalePathIsKeptWhenBookmarkAgrees() throws {
        let dir = makeTempDir()
        let file = makeFile("a.txt", in: dir)
        let item = ShelfItem(path: file.standardizedFileURL.path, bookmark: ShelfItem.makeBookmark(file), addedAt: .now)
        let resolved = try #require(item.resolve())
        #expect(resolved.item == item)
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
