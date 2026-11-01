import AppKit
import Foundation
import Testing
@testable import ClipboardFeature

/// Lane W5A: the history is the user's data, and the registry's stop (kill switch, switch off, safe mode) must stop
/// the recorder. Fakes only: a private pasteboard, a private notification center, a throwaway defaults suite and
/// temporary folders. Nothing reads the real pasteboard or the real history.
@Suite @MainActor struct ClipboardLifecycleTests {
    /// The file as our store writes it today (`ClipboardEntry.encode`). Synthetic values only.
    static let currentFormat = """
    [
      {"id":"BBBBBBBB-0000-0000-0000-000000000001","kind":"text","text":"synthetic pinned","filePaths":[],
       "sourceBundleID":"com.example.a","copiedAt":814980691.5,"pinned":true,"futureKey":{"x":1}},
      {"id":"BBBBBBBB-0000-0000-0000-000000000002","kind":"image","text":"","filePaths":[],
       "copiedAt":814980600.0,"imageFile":"BBBBBBBB-0000-0000-0000-000000000002.png","imageHash":"abc",
       "imageWidth":1,"imageHeight":1,"pinned":false},
      {"id":"BBBBBBBB-0000-0000-0000-000000000003","kind":"files","text":"x","filePaths":["/tmp/synthetic-x"],
       "copiedAt":814980500.0,"pinned":false}
    ]
    """
    static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02, 0x03])

    func seededDirectory(_ json: String = currentFormat) throws -> URL {
        let dir = makeTempDir()
        try json.write(to: dir.appendingPathComponent("ClipboardHistory.json"), atomically: true, encoding: .utf8)
        let images = dir.appendingPathComponent("ClipboardImages", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try Self.png.write(to: images.appendingPathComponent("BBBBBBBB-0000-0000-0000-000000000002.png"))
        return dir
    }

    struct Rig {
        let model: ClipboardModel
        let pasteboard: NSPasteboard
        let center: NotificationCenter
        let defaults: TempDefaults
        let directory: URL
    }

    func rig(directory: URL? = nil) throws -> Rig {
        let td = TempDefaults()
        let pb = makePasteboard()
        let center = NotificationCenter()
        let dir = try directory ?? seededDirectory()
        let model = ClipboardModel(dataDirectory: dir, pasteboard: pb,
                                   settings: { ClipboardSettings(defaults: td.defaults) },
                                   accessibilityTrusted: { true }, postAccess: { true },
                                   sendPaste: { .posted }, notify: { _ in }, hotkey: FakeHotkey(),
                                   stopCenter: center)
        return Rig(model: model, pasteboard: pb, center: center, defaults: td, directory: dir)
    }

    // MARK: Kill switch

    @Test func stopStopsMonitoringAndStartArmsItAgainWithoutTouchingTheHistory() throws {
        let r = try rig()
        let file = r.directory.appendingPathComponent("ClipboardHistory.json")
        let before = try Data(contentsOf: file)
        #expect(!r.model.isMonitoring)
        r.model.start()
        defer { r.model.stop() }
        #expect(r.model.isMonitoring)
        #expect(r.model.entries.count == 3)

        r.model.stop()
        #expect(!r.model.isMonitoring, "nothing copied from now on is recorded")
        #expect(r.model.entries.count == 3, "what was recorded stays")
        r.model.stop()   // idempotent
        #expect(!r.model.isMonitoring)

        r.model.start()
        #expect(r.model.isMonitoring)
        #expect(r.model.entries.count == 3, "a restart does not reload or drop the list")
        #expect(try Data(contentsOf: file) == before, "stop and start never rewrite the history file")
    }

    @Test func theRegistrysStopNameStopsAStartedModelOnly() async throws {
        let r = try rig()
        r.center.post(name: ClipboardFeature.stopRequested, object: nil)   // not started: nothing to stop, no crash
        #expect(!r.model.isMonitoring)

        r.model.start()
        defer { r.model.stop() }
        #expect(r.model.isMonitoring)
        r.center.post(name: ClipboardFeature.stopRequested, object: nil)
        #expect(await eventually(timeout: 120) { !r.model.isMonitoring })
        #expect(r.model.entries.count == 3)

        r.model.start()   // the registry starting it again (switch back on, kill switch off)
        #expect(r.model.isMonitoring)
        r.center.post(name: ClipboardFeature.stopRequested, object: nil)
        #expect(await eventually(timeout: 120) { !r.model.isMonitoring }, "the observer survives a restart")
    }

    @Test func aStoppedModelReleasesThePlainPasteHotkeyAndTheNextStartTakesItBack() throws {
        let td = TempDefaults()
        td.defaults.set(true, forKey: "pastePlainEnabled")
        let hotkey = FakeHotkey()
        let model = ClipboardModel(dataDirectory: makeTempDir(), pasteboard: makePasteboard(),
                                   settings: { ClipboardSettings(defaults: td.defaults) },
                                   accessibilityTrusted: { true }, sendPaste: { .posted }, notify: { _ in },
                                   hotkey: hotkey, stopCenter: NotificationCenter())
        model.start()
        #expect(hotkey.registered?.keyCode == 9)
        model.stop()
        #expect(hotkey.registered == nil && !model.isMonitoring)
        model.start()
        #expect(hotkey.registered?.keyCode == 9 && model.isMonitoring)
        model.stop()
    }

    // MARK: The file as it is today

    @Test func ourCurrentFileRoundTripsWithPinsImagesAndUnknownKeysDropped() throws {
        let dir = try seededDirectory()
        let store = ClipboardHistoryStore(directory: dir, limit: 50)
        store.load()
        #expect(store.entries.map(\.id) == ["BBBBBBBB-0000-0000-0000-000000000001",
                                            "BBBBBBBB-0000-0000-0000-000000000002",
                                            "BBBBBBBB-0000-0000-0000-000000000003"])
        #expect(store.entries[0].pinned && !store.entries[1].pinned)
        store.save()

        let again = ClipboardHistoryStore(directory: dir, limit: 50)
        again.load()
        #expect(again.entries == store.entries, "load, save, load is the identity")
        #expect(posix(dir.appendingPathComponent("ClipboardHistory.json")) == 0o600)
        let image = try #require(again.imageURL(for: again.entries[1]))
        #expect(try Data(contentsOf: image) == Self.png, "the image file is never rewritten")
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent(ClipboardHistoryStore.repairBackupName).path),
                "a file that decodes completely needs no backup")
    }

    @Test func aFileWithSomethingUnreadableIsKeptByteForByteBeforeTheFirstSave() throws {
        // The last "]" closes the array (every "filePaths":[] above it must stay as it is).
        let closed = Self.currentFormat.trimmingCharacters(in: .whitespacesAndNewlines)
        let broken = String(closed.dropLast()) + ",{\"id\":\"x\",\"kind\":\"hologram\",\"copiedAt\":1.0}]"
        let dir = try seededDirectory(broken)
        let original = try Data(contentsOf: dir.appendingPathComponent("ClipboardHistory.json"))
        let store = ClipboardHistoryStore(directory: dir, limit: 50)
        store.load()
        #expect(store.entries.count == 3)
        let backup = dir.appendingPathComponent(ClipboardHistoryStore.repairBackupName)
        #expect(try Data(contentsOf: backup) == original)
        #expect(posix(backup) == 0o600)

        store.addText("a new copy", source: nil)   // rewrites ClipboardHistory.json without the unreadable entry
        #expect(try Data(contentsOf: dir.appendingPathComponent("ClipboardHistory.json")) != original)
        #expect(try Data(contentsOf: backup) == original, "the backup is the file as it was found")

        // A later damaged file never replaces the first backup: the first one is the closest to what the user had.
        try Data("{ not json".utf8).write(to: dir.appendingPathComponent("ClipboardHistory.json"))
        let second = ClipboardHistoryStore(directory: dir, limit: 50)
        second.load()
        #expect(try Data(contentsOf: backup) == original)
    }

    @Test func aFileThatIsNotJsonIsKeptAndLoadsEmpty() throws {
        let dir = makeTempDir()
        let junk = Data("not json at all".utf8)
        try junk.write(to: dir.appendingPathComponent("ClipboardHistory.json"))
        let store = ClipboardHistoryStore(directory: dir, limit: 50)
        store.load()
        #expect(store.entries.isEmpty)
        #expect(try Data(contentsOf: dir.appendingPathComponent(ClipboardHistoryStore.repairBackupName)) == junk)
    }

    @Test func anEmptyFileOrNoFileMakesNoBackup() throws {
        let dir = makeTempDir()
        let store = ClipboardHistoryStore(directory: dir, limit: 50)
        store.load()
        try Data().write(to: dir.appendingPathComponent("ClipboardHistory.json"))
        store.load()
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent(ClipboardHistoryStore.repairBackupName).path))
    }

    // MARK: Migrated preferences the old app honoured

    @Test func theOldIgnoredAppsListAndTheImagesToggleAreHonoured() {
        let d = TempDefaults()
        #expect(ClipboardSettings(defaults: d.defaults).includeImagesAndFiles, "absent means on, as before")
        #expect(ClipboardSettings(defaults: d.defaults).excludedBundleIDs.isEmpty)
        d.defaults.set(["com.example.vault"], forKey: "clipboardHistoryIgnoredApps")
        d.defaults.set(["com.example.other"], forKey: "clipboardExcludedBundleIDs")
        d.defaults.set(false, forKey: "clipboardHistoryIncludeImagesFiles")
        let s = ClipboardSettings(defaults: d.defaults)
        #expect(s.excludedBundleIDs == ["com.example.vault", "com.example.other"])
        #expect(!s.includeImagesAndFiles)
    }

    final class Seen { var captures: [PasteboardCapture?] = [] }

    @Test func withImagesAndFilesOffOnlyTextIsRecorded() throws {
        let td = TempDefaults()
        let pb = makePasteboard()
        let seen = Seen()
        let w = PasteboardWatcher(pasteboard: pb)
        w.settings = { ClipboardSettings(defaults: td.defaults) }
        w.frontmostBundleID = { "com.example.app" }
        w.onChange = { _, capture, _ in seen.captures.append(capture) }

        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try #require(rep.representation(using: .png, properties: [:]))
        pb.clearContents(); pb.setData(png, forType: .png)
        w.poll()
        guard case .image? = seen.captures.last ?? nil else { Issue.record("an image is recorded by default"); return }

        td.defaults.set(false, forKey: "clipboardHistoryIncludeImagesFiles")
        pb.clearContents(); pb.setData(png, forType: .png)
        w.poll()
        #expect(seen.captures.last == .some(nil), "no image with the toggle off")

        pb.clearContents(); pb.setString("plain words", forType: .string)
        w.poll()
        #expect(seen.captures.last == .some(.text("plain words")), "text is still recorded")

        pb.clearContents(); pb.writeObjects([URL(fileURLWithPath: "/tmp/synthetic-file") as NSURL])
        w.poll()
        if case .files? = seen.captures.last ?? nil { Issue.record("a file path is recorded with the toggle off") }

        td.defaults.set(true, forKey: "clipboardHistoryIncludeImagesFiles")
        pb.clearContents(); pb.writeObjects([URL(fileURLWithPath: "/tmp/synthetic-file") as NSURL])
        w.poll()
        #expect(seen.captures.last == .some(.files(["/tmp/synthetic-file"])))
    }

    @Test func aConcealedOrTransientCopyIsNeverRecordedWhateverTheToggles() {
        let td = TempDefaults()
        let pb = makePasteboard()
        let seen = Seen()
        let w = PasteboardWatcher(pasteboard: pb)
        w.settings = { ClipboardSettings(defaults: td.defaults) }
        w.frontmostBundleID = { "com.example.app" }
        w.onChange = { _, capture, _ in seen.captures.append(capture) }
        for marker in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
                       "org.nspasteboard.AutoGeneratedType", "com.agilebits.onepassword"] {
            pb.clearContents()
            pb.setString("synthetic secret", forType: .string)
            pb.setData(Data(), forType: .init(marker))
            w.poll()
            #expect(seen.captures.last == .some(nil), "\(marker) is never stored")
        }
    }
}
