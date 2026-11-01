import Foundation
import Testing
@testable import ShelfFeature

/// The island tab after lane W5B: the items are the ported shelf's, the model keeps only the segment and Downloads.
@Suite @MainActor struct ShelfTabTests {
    private func model(downloads: Bool = false) -> ShelfModel {
        let defaults = MemoryDefaults()
        defaults.set(downloads, forKey: "shelfDownloadsEnabled")  // never touch the real Downloads folder
        return ShelfModel(settings: ShelfSettings(defaults: defaults), downloadsDirectory: makeTempDir())
    }

    @Test func theTabKeepsItsIdentityTitleAndIcon() {
        let tab = ShelfFeature.tab()
        #expect(tab.id == "shelf" && tab.title == "Étagère" && tab.systemImage == "tray.and.arrow.down")
    }

    @Test func twoSegmentsShelfFirst() {
        #expect(ShelfSegment.allCases == [.shelf, .downloads])
        #expect(model().segment == .shelf)
    }

    @Test func downloadsOffStartsNoWatcherAndStartIsIdempotent() {
        let m = model(downloads: false)
        m.start()
        m.start()
        #expect(!m.downloadsEnabled)
        #expect(m.downloads.items.isEmpty)
        m.refreshDownloads()  // no monitor: a no-op, never a crash
    }

    /// A fake folder watcher: hands out a real descriptor, so "the DispatchSource was cancelled" is observable as
    /// "its descriptor was closed" (the cancel handler closes it).
    private final class FakeWatch: @unchecked Sendable {
        private let lock = NSLock()
        private var _fds: [Int32] = []
        var fds: [Int32] { lock.withLock { _fds } }
        var fileSystem: DownloadsFileSystem {
            DownloadsFileSystem(
                list: { _, _, _, _ in DownloadsSnapshot(state: .ok, items: [], hasPending: false) },
                openForEvents: { [self] path in
                    let fd = open(path, O_EVTONLY)
                    lock.withLock { _fds.append(fd) }
                    return fd
                })
        }
    }

    private func isOpen(_ fd: Int32) -> Bool { fcntl(fd, F_GETFD) != -1 }

    private func waitUntil(timeout: TimeInterval = 120, _ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    @Test func stopCancelsTheDownloadsWatcherAndTheNextStartArmsAgain() async {
        let defaults = MemoryDefaults()
        defaults.set(true, forKey: "shelfDownloadsEnabled")
        let watch = FakeWatch()
        let m = ShelfModel(settings: ShelfSettings(defaults: defaults), downloadsDirectory: makeTempDir(),
                           fileSystem: watch.fileSystem)
        m.start()
        #expect(await waitUntil { watch.fds.count == 1 })
        let first = watch.fds[0]
        #expect(first >= 0 && isOpen(first), "the watcher is attached")

        m.stop()
        #expect(await waitUntil { !isOpen(first) }, "stop() cancels the DispatchSource, which closes the descriptor")

        m.stop()  // idempotent
        m.start()
        #expect(await waitUntil { watch.fds.count == 2 }, "a restart after a stop arms a fresh watcher")
        m.stop()
    }

    @Test func stopBeforeAnyStartIsANoOp() {
        let m = model(downloads: true)
        m.stop()
        m.stop()
    }

    @Test func theAppDelegateRegistersTheShelfStopper() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/MacIsland/AppDelegate.swift"),
                                encoding: .utf8)
        #expect(source.contains("\"shelf\": { ShelfFeature.stop() }"), "without it the Downloads watcher runs after a kill switch")
    }

    @Test func revealOfAMissingPathDoesNothing() {
        // A path that does not exist is ignored (no Finder window, no crash).
        model().reveal(path: "/nonexistent/w5b/missing.txt")
        model().reveal(path: "")
    }

    @Test func dragProviderCarriesTheFileURLOnly() {
        let provider = model().dragProvider(path: "/tmp/w5b-x.txt")
        #expect(provider.hasItemConformingToTypeIdentifier("public.file-url"))
    }
}
