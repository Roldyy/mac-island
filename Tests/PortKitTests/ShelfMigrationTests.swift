import Foundation
import Testing
@testable import PortKit

/// Lane W5B: the one-time import of Mac Island's own shelf store (`Shelf.json`) into the ported one (`shelfItems`),
/// the format fixtures of both stores, and what the ported restore does with a file that moved or is gone. Every
/// file lives in a temporary directory; the defaults are the fenced test suite, never the real preferences.
@MainActor
@Suite(.serialized) struct ShelfMigrationTests {
    /// The exact shape our retired store wrote: `ShelfItem` with `JSONEncoder` and `.secondsSince1970`.
    struct OldItem: Codable {
        var id: UUID
        var path: String
        var bookmark: Data?
        var addedAt: Date
    }

    static func oldFile(_ items: [OldItem]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(items)
    }

    func makeDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("w5b-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func bookmark(_ url: URL) throws -> Data {
        try url.bookmarkData(includingResourceValuesForKeys: [.fileResourceIdentifierKey], relativeTo: nil)
    }

    func write(_ name: String, in dir: URL, bytes: Int = 4) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    func shelfItems(_ defaults: UserDefaults) -> ShelfStoreLoad {
        ShelfPersistenceSupport.load(defaults.data(forKey: DefaultsKey.shelfItems))
    }

    static func posix(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int
    }

    // MARK: Our format, read by the port

    @Test func ourOldFormatIsUnreadableToThePortedStoreWhichIsWhyItIsConvertedOnce() throws {
        let dir = try makeDir()
        let file = try write("a.txt", in: dir)
        let data = try Self.oldFile([OldItem(id: UUID(), path: file.path, bookmark: nil, addedAt: Date())])
        #expect(ShelfPersistenceSupport.load(data) == .unreadable, "no `kind`: every entry fails, so nothing is restored")
        #expect(ShelfLegacyMigration.legacyEntries(from: data)?.count == 1)
    }

    @Test func aFixtureOfOurStoreWithRealBookmarksImportsWholeAndInOrder() throws {
        try PortHostFixture.isolated { defaults in
            let data = try makeDir()
            let files = try makeDir()
            let a = try write("a.txt", in: files)
            let b = try write("b.pdf", in: files)
            let idA = UUID(), idB = UUID()
            let original = try Self.oldFile([
                OldItem(id: idA, path: a.path, bookmark: try bookmark(a), addedAt: Date(timeIntervalSince1970: 1_700_000_000)),
                OldItem(id: idB, path: b.path, bookmark: nil, addedAt: Date(timeIntervalSince1970: 1_700_000_100)),
            ])
            let source = data.appendingPathComponent("Shelf.json")
            try original.write(to: source)

            #expect(ShelfLegacyMigration.run(dataDirectory: data, defaults: defaults) == .imported(added: 2))

            guard case let .items(items) = shelfItems(defaults) else { Issue.record("the blob must read whole"); return }
            #expect(items.map(\.id) == [idA, idB], "order and ids kept")
            #expect(items.map(\.kind) == [.file, .file])
            #expect(items.map(\.title) == ["a.txt", "b.pdf"])
            #expect(items.map(\.path) == [a.path, b.path])
            #expect(items[0].bookmark != nil && items[1].bookmark == nil)
            #expect(defaults.bool(forKey: ShelfLegacyMigration.markerKey))

            // The original and the files it names are untouched, and the backup is an exact owner-only copy.
            #expect(try Data(contentsOf: source) == original, "Shelf.json is never rewritten or deleted")
            let backup = data.appendingPathComponent(ShelfLegacyMigration.backupFileName)
            #expect(try Data(contentsOf: backup) == original)
            #expect(Self.posix(backup) == 0o600)
            #expect(FileManager.default.fileExists(atPath: a.path) && FileManager.default.fileExists(atPath: b.path))

            // Second run: nothing more happens.
            let blob = defaults.data(forKey: DefaultsKey.shelfItems)
            #expect(ShelfLegacyMigration.run(dataDirectory: data, defaults: defaults) == .alreadyDone)
            #expect(defaults.data(forKey: DefaultsKey.shelfItems) == blob)
        }
    }

    @Test func aLiteralFixtureOfOurFileDecodesTolerantlyPerEntry() throws {
        let json = """
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","path":"/tmp/one.txt","addedAt":1700000000},
         {"id":"not-a-uuid","path":"/tmp/two.txt","addedAt":1700000001},
         {"path":"/tmp/three.txt","bookmark":"AAEC","addedAt":1700000002},
         {"nothing":true},
         {"path":"","addedAt":1},
         {"path":"/tmp/one.txt","addedAt":2}]
        """
        let entries = try #require(ShelfLegacyMigration.legacyEntries(from: Data(json.utf8)))
        #expect(entries.map(\.path) == ["/tmp/one.txt", "/tmp/two.txt", "/tmp/three.txt"],
                "an entry with no path never hides the others; a bad id is renewed; a repeated path is kept once")
        #expect(entries.first?.id == UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        #expect(entries.last?.bookmark == Data([0, 1, 2]))
        #expect(ShelfLegacyMigration.legacyEntries(from: Data("{}".utf8)) == nil, "not a list")
        #expect(ShelfLegacyMigration.legacyEntries(from: Data("junk".utf8)) == nil)
    }

    // MARK: Safety

    @Test func nothingToImportMarksTheMigrationAndWritesNothing() throws {
        try PortHostFixture.isolated { defaults in
            let data = try makeDir()
            #expect(ShelfLegacyMigration.run(dataDirectory: data, defaults: defaults) == .nothingToImport)
            #expect(defaults.object(forKey: DefaultsKey.shelfItems) == nil)
            #expect(defaults.bool(forKey: ShelfLegacyMigration.markerKey))
        }
        try PortHostFixture.isolated { defaults in
            let data = try makeDir()
            try Self.oldFile([]).write(to: data.appendingPathComponent("Shelf.json"))
            #expect(ShelfLegacyMigration.run(dataDirectory: data, defaults: defaults) == .nothingToImport)
            #expect(!FileManager.default.fileExists(atPath: data.appendingPathComponent("Shelf.pre-port.json").path),
                    "no entry, no backup")
        }
    }

    @Test func anUnreadableOrNewerShelfItemsIsNeverOverwrittenAndTheImportRetries() throws {
        for blob: Any in [Data("not json".utf8),
                          Data(#"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"hologram","title":"x"}]"#.utf8),
                          "a string, not data"] {
            try PortHostFixture.isolated { defaults in
                let data = try makeDir()
                let file = try write("a.txt", in: data)
                try Self.oldFile([OldItem(id: UUID(), path: file.path, bookmark: nil, addedAt: Date())])
                    .write(to: data.appendingPathComponent("Shelf.json"))
                defaults.set(blob, forKey: DefaultsKey.shelfItems)
                #expect(ShelfLegacyMigration.run(dataDirectory: data, defaults: defaults) == .shelfItemsUnreadable)
                if let expected = blob as? Data { #expect(defaults.data(forKey: DefaultsKey.shelfItems) == expected) }
                #expect(defaults.bool(forKey: ShelfLegacyMigration.markerKey) == false, "retried at the next launch")
                #expect(!FileManager.default.fileExists(atPath: data.appendingPathComponent("Shelf.pre-port.json").path))
            }
        }
    }

    @Test func existingPortedItemsStayFirstAndAKnownPathIsNotAddedTwice() throws {
        try PortHostFixture.isolated { defaults in
            let data = try makeDir()
            let files = try makeDir()
            let a = try write("a.txt", in: files)
            let b = try write("b.txt", in: files)
            let kept = ShelfPersistedItem(id: UUID(), kind: .file, title: "a.txt", path: a.path)
            let text = ShelfPersistedItem(id: UUID(), kind: .text, title: "memo", text: "hello")
            defaults.set(try JSONEncoder().encode([kept, text]), forKey: DefaultsKey.shelfItems)
            try Self.oldFile([OldItem(id: UUID(), path: a.path, bookmark: nil, addedAt: Date()),
                              OldItem(id: UUID(), path: b.path, bookmark: nil, addedAt: Date())])
                .write(to: data.appendingPathComponent("Shelf.json"))
            #expect(ShelfLegacyMigration.run(dataDirectory: data, defaults: defaults) == .imported(added: 1))
            guard case let .items(items) = shelfItems(defaults) else { Issue.record("must read whole"); return }
            #expect(items.map(\.id).prefix(2) == [kept.id, text.id])
            #expect(items.count == 3 && items.last?.path == b.path)
        }
    }

    @Test func anExistingBackupIsNeverReplaced() throws {
        try PortHostFixture.isolated { defaults in
            let data = try makeDir()
            let file = try write("a.txt", in: data)
            let backup = data.appendingPathComponent("Shelf.pre-port.json")
            try Data("first copy".utf8).write(to: backup)
            try Self.oldFile([OldItem(id: UUID(), path: file.path, bookmark: nil, addedAt: Date())])
                .write(to: data.appendingPathComponent("Shelf.json"))
            #expect(ShelfLegacyMigration.run(dataDirectory: data, defaults: defaults) == .imported(added: 1))
            #expect(try Data(contentsOf: backup) == Data("first copy".utf8))
        }
    }

    @Test func aBackupThatCannotBeWrittenStopsTheImportBeforeAnythingChanges() throws {
        try PortHostFixture.isolated { defaults in
            let data = try makeDir()
            let file = try write("a.txt", in: data)
            try Self.oldFile([OldItem(id: UUID(), path: file.path, bookmark: nil, addedAt: Date())])
                .write(to: data.appendingPathComponent("Shelf.json"))
            #expect(ShelfLegacyMigration.run(dataDirectory: data, defaults: defaults, writeBackup: { _, _ in false })
                    == .backupFailed)
            #expect(!FileManager.default.fileExists(atPath: data.appendingPathComponent("Shelf.pre-port.json").path))
            #expect(defaults.object(forKey: DefaultsKey.shelfItems) == nil)
            #expect(defaults.bool(forKey: ShelfLegacyMigration.markerKey) == false)
        }
    }

    @Test func anUnreadableLegacyFileIsLeftAloneAndRetried() throws {
        try PortHostFixture.isolated { defaults in
            let data = try makeDir()
            let source = data.appendingPathComponent("Shelf.json")
            try Data("{ truncated".utf8).write(to: source)
            #expect(ShelfLegacyMigration.run(dataDirectory: data, defaults: defaults) == .legacyUnreadable)
            #expect(try Data(contentsOf: source) == Data("{ truncated".utf8))
            #expect(defaults.bool(forKey: ShelfLegacyMigration.markerKey) == false)
        }
    }

    // MARK: What the ported restore does with a file that moved or is gone

    @Test func aMovedFileIsFoundAgainThroughItsBookmarkAndAGoneOneIsDroppedWithoutACrash() throws {
        let files = try makeDir()
        let moved = try write("before.txt", in: files)
        let gone = try write("gone.txt", in: files)
        let kept = try write("kept.txt", in: files)
        let bookmarkMoved = try bookmark(moved)
        let bookmarkGone = try bookmark(gone)
        let after = files.appendingPathComponent("after.txt")
        try FileManager.default.moveItem(at: moved, to: after)
        try FileManager.default.removeItem(at: gone)

        let entries = [
            ShelfPersistedItem(id: UUID(), kind: .file, title: "before.txt", path: moved.path, bookmark: bookmarkMoved),
            ShelfPersistedItem(id: UUID(), kind: .file, title: "gone.txt", path: gone.path, bookmark: bookmarkGone),
            ShelfPersistedItem(id: UUID(), kind: .file, title: "junk.txt", path: "/nowhere/junk.txt", bookmark: Data("junk".utf8)),
            ShelfPersistedItem(id: UUID(), kind: .file, title: "kept.txt", path: kept.path),
        ]
        let resolve: (Data) -> String? = { data in
            var stale = false
            return (try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil,
                             bookmarkDataIsStale: &stale))?.path
        }
        let sanitized = ShelfPersistenceSupport.sanitized(
            entries, fileExists: { FileManager.default.fileExists(atPath: $0) }, resolveBookmark: resolve)
        #expect(sanitized.map(\.title) == ["after.txt", "kept.txt"],
                "the moved file follows its bookmark and takes its new name; the gone and the junk bookmark are dropped")
        #expect(sanitized.first?.path.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
                == after.resolvingSymlinksInPath().path)
        #expect(FileManager.default.fileExists(atPath: kept.path), "nothing of the person's was touched")
    }

    @Test func aFileOnAnUnmountedVolumeIsNotJudgedGone() {
        #expect(ShelfPersistenceSupport.unmountedVolumeRoot(of: "/Volumes/Backup/x/y.txt") == "/Volumes/Backup")
        #expect(ShelfPersistenceSupport.unmountedVolumeRoot(of: "/Users/x/y.txt") == nil)
    }

    // MARK: Scratchpad: our file in the ported store

    static let ourScratchpadJSON = """
    {"pads":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Note 1","text":"alpha"},
             {"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Courses","text":"lait\\npain"}],
     "selectedID":"7F9619FF-8B86-D011-B42D-00C04FC964FF"}
    """

    @Test func ourClipboardScratchpadFileReadsInThePortedStoreAndIsBackedUpFirst() throws {
        try PortHostFixture.isolated { defaults in
            let dir = try makeDir()
            let original = Data(Self.ourScratchpadJSON.utf8)
            try original.write(to: dir.appendingPathComponent("Scratchpad.json"))

            #expect(ScratchpadLegacyBackup.run(directory: dir) == .backedUp)
            #expect(ScratchpadLegacyBackup.run(directory: dir) == .alreadyBackedUp, "never replaced")
            let backup = dir.appendingPathComponent("Scratchpad.pre-port.json")
            #expect(try Data(contentsOf: backup) == original)
            #expect(Self.posix(backup) == 0o600)

            var store = ScratchpadStore(directoryURL: dir, defaults: defaults)
            let document = try store.load(defaultName: "Note", retention: .never, now: Date())
            #expect(document.pads.map(\.name) == ["Note 1", "Courses"])
            #expect(document.pads.map(\.text) == ["alpha", "lait\npain"])
            #expect(document.selectedID == UUID(uuidString: "7F9619FF-8B86-D011-B42D-00C04FC964FF"))

            // The ported store rewrote the file in its own codec: our reader's keys are still there.
            let rewritten = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("Scratchpad.json")))
            let pads = try #require((rewritten as? [String: Any])?["pads"] as? [[String: Any]])
            #expect(pads.count == 2 && pads.allSatisfy { $0["id"] is String && $0["name"] is String && $0["text"] is String })
            #expect((rewritten as? [String: Any])?["selectedID"] is String)
            #expect(try Data(contentsOf: backup) == original, "the backup keeps the pre-port bytes")
        }
    }

    @Test func morePadsThanTheLimitAreCutByThePortedStoreButTheBackupKeepsThemAll() throws {
        try PortHostFixture.isolated { defaults in
            let dir = try makeDir()
            let ids = (0..<14).map { _ in UUID().uuidString }
            let pads = ids.enumerated().map { #"{"id":"\#($1)","name":"P\#($0)","text":"t\#($0)"}"# }
            let json = Data(#"{"pads":[\#(pads.joined(separator: ","))],"selectedID":"\#(ids[13])"}"#.utf8)
            try json.write(to: dir.appendingPathComponent("Scratchpad.json"))
            _ = ScratchpadLegacyBackup.run(directory: dir)
            var store = ScratchpadStore(directoryURL: dir, defaults: defaults)
            let document = try store.load(defaultName: "Note", retention: .never, now: Date())
            #expect(document.pads.count == ScratchpadDocument.maximumPadCount)
            #expect(try Data(contentsOf: dir.appendingPathComponent("Scratchpad.pre-port.json")) == json)
        }
    }

    @Test func aScratchpadFileTheStoreCannotReadIsNeverRewritten() throws {
        try PortHostFixture.isolated { defaults in
            let dir = try makeDir()
            let junk = Data(#"{"pads":[{"id":"not-a-uuid","name":"x","text":"y"}],"selectedID":"z"}"#.utf8)
            let file = dir.appendingPathComponent("Scratchpad.json")
            try junk.write(to: file)
            var store = ScratchpadStore(directoryURL: dir, defaults: defaults)
            #expect(throws: (any Error).self) { try store.load(defaultName: "Note", retention: .never, now: Date()) }
            #expect(store.save(.initial(defaultName: "Note")) == false, "a failed read never authorizes a save")
            #expect(try Data(contentsOf: file) == junk)
            #expect(ScratchpadLegacyBackup.run(directory: dir) == .backedUp)
        }
        #expect(ScratchpadLegacyBackup.run(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("w5b-missing-\(UUID().uuidString)")) == .noFile)
    }
}
