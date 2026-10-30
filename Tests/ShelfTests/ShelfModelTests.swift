import Foundation
import Testing
@testable import ShelfFeature

@Suite @MainActor struct ShelfModelTests {
    private func model() -> ShelfModel {
        let defaults = MemoryDefaults()
        defaults.set(false, forKey: "shelfDownloadsEnabled") // never touch the real Downloads folder
        return ShelfModel(settings: ShelfSettings(defaults: defaults), dataDirectory: makeTempDir())
    }

    @Test func movedFileKeepsTileDragAndRevealOnTheSameURL() throws {
        let dir = makeTempDir()
        let file = makeFile("a.txt", in: dir)
        let m = model()
        m.add([file])
        let before = try #require(m.items.first)
        try FileManager.default.moveItem(at: file, to: dir.appendingPathComponent("b.txt"))
        m.refreshItems()
        let item = try #require(m.items.first)
        #expect(item.id == before.id)
        #expect(item.displayName == "b.txt")
        #expect(m.isAvailable(item))
        #expect(m.url(for: item)?.lastPathComponent == "b.txt")
        // the persisted shelf carries the new path
        let reloaded = ShelfStore(directory: m.storeDirectoryForTests).load()
        #expect(reloaded.first?.displayName == "b.txt")
    }

    @Test func lookAlikeAtTheOldPathMakesTheTileUnavailableAndNothingIsDelivered() throws {
        let dir = makeTempDir()
        let file = makeFile("a.txt", in: dir)
        let m = model()
        m.add([file])
        try FileManager.default.moveItem(at: file, to: dir.appendingPathComponent("b.txt"))
        makeFile("a.txt", in: dir, bytes: 99)
        m.refreshItems()
        let item = try #require(m.items.first)
        #expect(!m.isAvailable(item))
        #expect(m.url(for: item) == nil)
    }

    @Test func removedAndClearedItemsLeaveNoResolution() throws {
        let dir = makeTempDir()
        let m = model()
        m.add([makeFile("a.txt", in: dir), makeFile("b.txt", in: dir)])
        #expect(m.resolved.count == 2)
        m.remove(m.items[0])
        #expect(m.resolved.count == 1)
        m.clear()
        #expect(m.resolved.isEmpty)
    }
}
