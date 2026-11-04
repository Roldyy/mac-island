import AppKit
import IslandKit
import Testing
@testable import ClipboardFeature

/// Lane 1 (perf): the watcher follows the shared hub instead of keeping its own 0.5 s timer.
@Suite @MainActor struct PasteboardWatcherHubTests {
    @MainActor final class Rig {
        var live = 0
        var tickHandler: (@MainActor () -> Void)?
        var count = 0
        lazy var hub = PasteboardChangeHub(
            reader: { [unowned self] done in done(count) },
            schedule: { [unowned self] _, tick in live += 1; tickHandler = tick; return { [unowned self] in live -= 1; tickHandler = nil } })
    }

    private func make(_ rig: Rig) -> (PasteboardWatcher, NSPasteboard, TempDefaults, [PasteboardCapture?]) {
        let pb = makePasteboard()
        let td = TempDefaults()
        let w = PasteboardWatcher(pasteboard: pb, hub: rig.hub)
        w.settings = { ClipboardSettings(defaults: td.defaults) }
        w.frontmostBundleID = { "com.example.app" }
        return (w, pb, td, [])
    }

    @Test func startSubscribesAndStopLeavesNothingRunning() {
        let rig = Rig()
        let (w, _, td, _) = make(rig); defer { _ = td }
        #expect(!w.isRunning && rig.live == 0)
        w.start()
        #expect(w.isRunning && rig.live == 1)
        w.start()
        #expect(rig.live == 1, "starting twice is one subscription")
        w.stop()
        #expect(!w.isRunning && rig.live == 0, "the last subscriber left: the hub's timer is gone")
    }

    @Test func aHubTickReportsAChangeOnce() {
        let rig = Rig()
        let (w, pb, td, _) = make(rig); defer { _ = td }
        final class Seen { var captures: [PasteboardCapture?] = [] }
        let seen = Seen()
        w.onChange = { _, capture, _ in seen.captures.append(capture) }
        w.start()
        pb.clearContents(); pb.setString("hello", forType: .string)
        rig.count = pb.changeCount
        rig.tickHandler?()
        rig.tickHandler?()
        #expect(seen.captures == [.text("hello")], "the second tick sees the same count: nothing new")
        w.stop()
    }

    @Test func aStaleCountFromBeforeOurOwnWriteIsNotACopy() {
        let rig = Rig()
        let (w, pb, td, _) = make(rig); defer { _ = td }
        final class Seen { var n = 0 }
        let seen = Seen()
        w.onChange = { _, _, _ in seen.n += 1 }
        w.start()
        let before = pb.changeCount
        pb.clearContents(); pb.setString("ours", forType: .string)   // the app's own write
        w.syncToCurrent()
        rig.count = before                                            // a read that started before that write lands now
        rig.tickHandler?()
        #expect(seen.n == 0, "a lower count is stale, never recorded back")
        w.stop()
    }
}
