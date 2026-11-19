import AppKit
import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import IslandExtrasFeature

@MainActor
@Suite struct NotesModelTests {
    @Test func everyEditIsSavedAndReloaded() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mis-notes-model-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = NotesModel(store: NotesStore(directory: dir))
        #expect(model.text == "")
        model.text = "Idée"
        #expect(NotesModel(store: NotesStore(directory: dir)).text == "Idée")
        #expect(!model.saveFailed)
    }

    @Test func aTextOverTheCapIsCut() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mis-notes-model-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = NotesModel(store: NotesStore(directory: dir))
        model.text = String(repeating: "x", count: NotesStore.maxLength + 10)
        #expect(model.text.count == NotesStore.maxLength && model.remaining == 0)
    }
}

@MainActor
@Suite struct ColoursModelTests {
    let bench = TestDefaults.make()

    @Test func aPickedColourIsRecordedCopiedAndPersisted() {
        defer { bench.cleanup() }
        var copied: [String] = []
        let model = ColoursModel(defaults: bench.defaults,
                                 picker: { done in done(NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1)) },
                                 copy: { copied.append($0) })
        model.pick()
        #expect(model.recent.hexes == ["#FF8000"] && copied == ["#FF8000"] && model.lastCopied == "#FF8000")
        #expect(!model.isPicking)
        #expect(RecentColours.load(from: bench.defaults).hexes == ["#FF8000"])
    }

    @Test func aCancelledPickChangesNothingAndFreesThePicker() {
        defer { bench.cleanup() }
        var copied: [String] = []
        let model = ColoursModel(defaults: bench.defaults, picker: { done in done(nil) }, copy: { copied.append($0) })
        model.pick()
        #expect(model.recent.hexes.isEmpty && copied.isEmpty && !model.isPicking)
    }

    @Test func onlyOneEyedropperAtATime() {
        defer { bench.cleanup() }
        var shown = 0
        let model = ColoursModel(defaults: bench.defaults, picker: { _ in shown += 1 }, copy: { _ in })
        model.pick(); model.pick()
        #expect(shown == 1 && model.isPicking)
    }

    @Test func clickingASwatchCopiesItAndClearForgetsThem() {
        defer { bench.cleanup() }
        var copied: [String] = []
        let model = ColoursModel(defaults: bench.defaults, picker: { _ in }, copy: { copied.append($0) })
        model.record("#123456")
        model.copyHex("#123456")
        #expect(copied == ["#123456"])
        model.clear()
        #expect(model.recent.hexes.isEmpty && RecentColours.load(from: bench.defaults).hexes.isEmpty)
    }
}

@MainActor
@Suite struct NetworkNoticeMonitorTests {
    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 2_000_000)
    }

    /// Sleep that returns at once, so a settle runs right after the observation with the clock the test sets.
    private func make(_ clock: Clock, posts: @escaping @MainActor (IslandActivity) -> Void) -> NetworkNoticeMonitor {
        NetworkNoticeMonitor(now: { clock.now }, post: posts, sleep: { _ in })
    }

    private func settled() async { for _ in 0..<5 { await Task.yield() } }

    @Test func nothingIsPostedForTheFirstStateThenALossAndARestoreAre() async {
        let clock = Clock()
        var posted: [String?] = []
        let monitor = make(clock) { posted.append($0.leading?.text) }
        monitor.start(); defer { monitor.stop() }
        monitor.received(online: true)
        clock.now += 2; await settled()
        #expect(posted.isEmpty, "launch state is the baseline")
        monitor.received(online: false)
        clock.now += 1.1; await settled()
        #expect(posted == ["Réseau perdu"])
        monitor.received(online: true)
        clock.now += 1.1; await settled()
        #expect(posted == ["Réseau perdu", "Réseau rétabli"])
    }

    @Test func aWakeFromSleepStaysQuietForAWhileButKeepsTrackOfTheState() async {
        let clock = Clock()
        var posted: [String?] = []
        let monitor = make(clock) { posted.append($0.leading?.text) }
        monitor.start(); defer { monitor.stop() }
        monitor.received(online: true); clock.now += 2; await settled()
        monitor.wokeUp()
        monitor.received(online: false); clock.now += 1.1; await settled()
        monitor.received(online: true); clock.now += 1.1; await settled()
        #expect(posted.isEmpty, "the path flaps while the Mac wakes: no notice during the quiet window")
        clock.now += NetworkNoticeMonitor.wakeQuiet + 1
        monitor.received(online: false); clock.now += 1.1; await settled()
        #expect(posted == ["Réseau perdu"], "after the window a real loss is announced again")
    }

    @Test func aStoppedMonitorIgnoresReadings() async {
        let clock = Clock()
        var posted = 0
        let monitor = make(clock) { _ in posted += 1 }
        monitor.received(online: true); clock.now += 2; await settled()
        monitor.received(online: false); clock.now += 2; await settled()
        #expect(posted == 0 && !monitor.isRunning)
    }
}
