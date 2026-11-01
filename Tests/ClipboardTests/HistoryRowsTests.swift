import AppKit
import Foundation
import Testing
@testable import ClipboardFeature

/// The rows of the history page that used to read "Bientôt": history shortcut, layout, menu bar preview, retention,
/// system clears. Private pasteboards, private defaults suites, private notification centers: nothing global.
@Suite @MainActor struct HistoryRowsTests {
    final class Sink { var previews: [String?] = []; var opened = 0 }

    struct Rig {
        let model: ClipboardModel
        let plain: FakeHotkey
        let history: UnregisteredHotkey
        let pasteboard: NSPasteboard
        let defaults: TempDefaults
        let sink: Sink
        let workspace: NotificationCenter
        let distributed: NotificationCenter
        let directory: URL
    }

    func rig(_ configure: (UserDefaults) -> Void = { _ in }, directory: URL = makeTempDir()) -> Rig {
        let td = TempDefaults()
        configure(td.defaults)
        let plain = FakeHotkey()
        let history = UnregisteredHotkey()
        let pb = makePasteboard()
        let sink = Sink()
        let workspace = NotificationCenter()
        let distributed = NotificationCenter()
        let model = ClipboardModel(
            dataDirectory: directory, pasteboard: pb, settings: { ClipboardSettings(defaults: td.defaults) },
            accessibilityTrusted: { true }, sendPaste: { .posted }, notify: { _ in },
            hotkey: plain, historyHotkey: history, openHistory: { sink.opened += 1 },
            previewSink: { sink.previews.append($0) },
            workspaceCenter: workspace, distributedCenter: distributed, stopCenter: NotificationCenter())
        return Rig(model: model, plain: plain, history: history, pasteboard: pb, defaults: td, sink: sink,
                   workspace: workspace, distributed: distributed, directory: directory)
    }

    // MARK: History shortcut

    @Test func theHistoryShortcutDefaultsToControlOptionCommandVAndOpensTheTab() {
        let r = rig()
        r.model.start(); defer { r.model.stop() }
        #expect(r.history.registered == ClipboardSettings.defaultHistoryShortcut)
        #expect(r.history.registered?.keyCode == 9 && r.history.registered?.modifiers == [.control, .option, .command])
        #expect(r.plain.registered?.modifiers == [.option, .command], "the paste-plain key is untouched")
        r.model.segment = .scratchpad
        r.history.press()
        #expect(r.sink.opened == 1)
        #expect(r.model.segment == .history, "it opens the history segment, not the scratchpad")
    }

    @Test func theSwitchAndTheRecordedShortcutAreFollowedLive() {
        let r = rig()
        r.model.start(); defer { r.model.stop() }
        r.defaults.defaults.set(false, forKey: "clipboardHistoryShortcutEnabled")
        r.model.settingsChanged()
        #expect(r.history.registered == nil)
        r.defaults.defaults.set(true, forKey: "clipboardHistoryShortcutEnabled")
        r.defaults.defaults.set("control+option+command:11", forKey: "clipboardHistoryShortcut")   // B
        r.model.settingsChanged()
        #expect(r.history.registered?.keyCode == 11)
        r.defaults.defaults.set(false, forKey: "clipboardHistoryEnabled")
        r.model.settingsChanged()
        #expect(r.history.registered == nil, "no history, no shortcut")
        #expect(r.model.historyShortcutStatus.isEmpty)
    }

    @Test func theHistoryKeyNeverTakesThePlainPasteCombination() {
        let r = rig { $0.set("option+command:9", forKey: "clipboardHistoryShortcut") }   // the paste-plain default
        r.model.start(); defer { r.model.stop() }
        #expect(r.plain.registered?.keyCode == 9, "paste plain keeps it")
        #expect(r.history.registered == nil)
        #expect(r.history.registerCalls.isEmpty, "never even asked Carbon for the same combination")
        #expect(r.model.historyShortcutStatus.contains("collage sans style"))
        // Moving the history key elsewhere frees the situation.
        r.defaults.defaults.set("control+option+command:11", forKey: "clipboardHistoryShortcut")
        r.model.settingsChanged()
        #expect(r.history.registered?.keyCode == 11 && r.model.historyShortcutStatus.isEmpty)
    }

    @Test func aKeyAnotherAppHoldsIsReportedAndTriedOncePerChange() {
        let r = rig()
        r.history.accept = false
        r.model.start(); defer { r.model.stop() }
        #expect(r.history.registered == nil)
        #expect(r.model.historyShortcutStatus.contains("indisponible"))
        let calls = r.history.registerCalls.count
        for _ in 0..<5 { r.model.settingsChanged() }
        #expect(r.history.registerCalls.count == calls, "unrelated defaults writes do not retry")
    }

    @Test func stopReleasesTheHistoryKey() {
        let r = rig()
        r.model.start()
        #expect(r.history.registered != nil)
        r.model.stop()
        #expect(r.history.registered == nil)
        r.model.start(); defer { r.model.stop() }
        #expect(r.history.registered != nil)
    }

    // MARK: Layout

    @Test func layoutReadsTheMigratedKeyAndFallsBackToTheList() {
        let r = rig()
        r.model.start(); defer { r.model.stop() }
        #expect(r.model.layout == .list)
        r.defaults.defaults.set("cards", forKey: "clipboardHistoryLayout")
        r.model.settingsChanged()
        #expect(r.model.layout == .cards)
        r.defaults.defaults.set("garbage", forKey: "clipboardHistoryLayout")
        r.model.settingsChanged()
        #expect(r.model.layout == .list)
    }

    // MARK: Menu bar preview

    @Test func previewTextIsOneLineAndNeverLongerThanTheLength() {
        #expect(ClipboardPreview.line("hello", limit: 20) == "hello")
        #expect(ClipboardPreview.line("a  b\n\tc", limit: 20) == "a b c")
        let long = String(repeating: "abcdefghij ", count: 10)
        for n in ClipboardSettings.menuBarPreviewLengthRange {
            let shown = ClipboardPreview.line(long, limit: n)
            #expect((shown?.count ?? 0) <= n, "length \(n)")
            #expect(shown?.hasSuffix("…") == true)
        }
        #expect(ClipboardPreview.line(String(repeating: "x", count: 100), limit: 1)?.count == 5, "clamped to the smallest length")
        #expect(ClipboardPreview.line("   \n ", limit: 20) == nil)
        #expect(ClipboardPreview.line("é😀é😀é😀é😀é😀é😀é😀", limit: 6)?.count == 6, "characters, not bytes")
    }

    @Test func previewShowsTheNewestCopyWhenOnAndNothingWhenOff() {
        let r = rig { $0.set(true, forKey: "clipboardHistoryMenuBarPreview"); $0.set(10, forKey: "clipboardHistoryMenuBarPreviewLength") }
        r.model.start(); defer { r.model.stop() }
        #expect(r.sink.previews.isEmpty, "empty history: nothing to show")
        r.pasteboard.clearContents(); r.pasteboard.setString("une copie vraiment tres longue", forType: .string)
        r.model.pollNow()
        #expect(r.sink.previews.last == "une copie…")
        #expect((r.sink.previews.last??.count ?? 99) <= 10)
        r.defaults.defaults.set(false, forKey: "clipboardHistoryMenuBarPreview")
        r.model.settingsChanged()
        #expect(r.sink.previews.last == .some(nil), "turning it off removes the text")
        r.model.stop()
    }

    @Test func aConcealedCopyNeverReachesThePreview() {
        let r = rig { $0.set(true, forKey: "clipboardHistoryMenuBarPreview") }
        r.model.start(); defer { r.model.stop() }
        r.pasteboard.clearContents()
        r.pasteboard.setString("secret-value", forType: .string)
        r.pasteboard.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        r.model.pollNow()
        #expect(r.sink.previews.isEmpty)
        #expect(r.model.entries.isEmpty)
    }

    @Test func stoppingTheFeatureClearsThePreview() {
        let r = rig { $0.set(true, forKey: "clipboardHistoryMenuBarPreview") }
        r.model.start()
        r.pasteboard.clearContents(); r.pasteboard.setString("visible", forType: .string)
        r.model.pollNow()
        #expect(r.sink.previews.last == "visible")
        r.model.stop()
        #expect(r.sink.previews.last == .some(nil))
    }

    // MARK: Retention

    @Test func retentionDropsOldUnpinnedItemsButKeepsPinnedOnes() {
        let dir = makeTempDir()
        var now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let store = ClipboardHistoryStore(directory: dir, limit: 50, now: { now })
        store.addText("old", source: nil)
        store.addText("old pinned", source: nil)
        store.togglePin(id: store.entries[0].id)
        now = now.addingTimeInterval(6 * 86_400)
        store.addText("recent", source: nil)
        now = now.addingTimeInterval(2 * 86_400)   // "old" is 8 days old, "recent" 2
        #expect(!store.purge(olderThanDays: 0), "0 keeps everything")
        #expect(store.purge(olderThanDays: 7))
        #expect(store.entries.map(\.text).sorted() == ["old pinned", "recent"])
        #expect(!store.purge(olderThanDays: 7), "nothing more to drop")
        let reloaded = ClipboardHistoryStore(directory: dir, limit: 50, now: { now })
        reloaded.load()
        #expect(reloaded.entries.count == 2, "the purge is saved")
        #expect(reloaded.pinnedCount == 1 && reloaded.recentCount == 1)
    }

    @Test func retentionRunsAtLaunchAndOnCopy() throws {
        let dir = makeTempDir()
        let old = ClipboardHistoryStore(directory: dir, limit: 50, now: { Date().addingTimeInterval(-40 * 86_400) })
        old.addText("forty days ago", source: nil)
        let r = rig({ $0.set(30, forKey: "clipboardHistoryRetentionDays") }, directory: dir)
        r.model.start(); defer { r.model.stop() }
        #expect(r.model.entries.isEmpty, "purged at launch")
        r.pasteboard.clearContents(); r.pasteboard.setString("fresh", forType: .string)
        r.model.pollNow()
        #expect(r.model.entries.map(\.text) == ["fresh"])
    }

    @Test func changingTheRetentionPurgesAtOnce() {
        let dir = makeTempDir()
        let old = ClipboardHistoryStore(directory: dir, limit: 50, now: { Date().addingTimeInterval(-10 * 86_400) })
        old.addText("ten days ago", source: nil)
        let r = rig(directory: dir)
        r.model.start(); defer { r.model.stop() }
        #expect(r.model.entries.count == 1, "retention is Toujours")
        r.defaults.defaults.set(7, forKey: "clipboardHistoryRetentionDays")
        r.model.settingsChanged()
        #expect(r.model.entries.isEmpty)
    }

    // MARK: Pinned and recent counts, "Effacer non épinglés"

    @Test func countsAndClearUnpinnedKeepThePinnedOnes() {
        let r = rig()
        r.model.start(); defer { r.model.stop() }
        for t in ["a", "b", "c"] {
            r.pasteboard.clearContents(); r.pasteboard.setString(t, forType: .string)
            r.model.pollNow()
        }
        r.model.togglePin(r.model.entries[0])
        #expect(r.model.pinnedCount == 1 && r.model.recentCount == 2)
        r.model.clearUnpinned()
        #expect(r.model.entries.count == 1 && r.model.entries[0].pinned)
        #expect(r.model.pinnedCount == 1 && r.model.recentCount == 0)
    }

    @Test func clearUnpinnedOnAModelNeverStartedDoesNotWipeTheFile() throws {
        let dir = makeTempDir()
        let seed = ClipboardHistoryStore(directory: dir, limit: 50)
        seed.addText("pinned one", source: nil)
        seed.togglePin(id: seed.entries[0].id)
        seed.addText("recent one", source: nil)
        let r = rig(directory: dir)   // never started: the feature is off
        #expect(r.model.pinnedCount == 1 && r.model.recentCount == 1, "the page shows the real counts")
        r.model.clearUnpinned()
        let reloaded = ClipboardHistoryStore(directory: dir, limit: 50)
        reloaded.load()
        #expect(reloaded.entries.map(\.text) == ["pinned one"])
    }

    // MARK: Clearing the system pasteboard on sleep, display sleep and lock

    @Test func eachSystemClearWorksOnItsOwnAndLeavesTheHistoryAlone() async {
        let r = rig {
            $0.set(true, forKey: "clipboardAutoClearOnSleep")
            $0.set(true, forKey: "clipboardAutoClearOnDisplaySleep")
            $0.set(true, forKey: "clipboardAutoClearOnScreenLock")
        }
        r.model.start(); defer { r.model.stop() }
        r.pasteboard.clearContents(); r.pasteboard.setString("keep me in the history", forType: .string)
        r.model.pollNow()
        let triggers: [(NotificationCenter, Notification.Name)] = [
            (r.workspace, NSWorkspace.willSleepNotification),
            (r.workspace, NSWorkspace.screensDidSleepNotification),
            (r.distributed, SystemClearObserver.screenLockName),
        ]
        for (center, name) in triggers {
            r.pasteboard.clearContents(); r.pasteboard.setString("on the pasteboard", forType: .string)
            #expect(r.pasteboard.string(forType: .string) != nil)
            center.post(name: name, object: nil)
            #expect(await eventually { r.pasteboard.string(forType: .string) == nil }, "\(name.rawValue)")
        }
        #expect(r.model.entries.map(\.text) == ["keep me in the history"])
    }

    @Test func aSystemClearThatIsOffDoesNothing() async {
        let r = rig { $0.set(true, forKey: "clipboardAutoClearOnScreenLock") }
        r.model.start(); defer { r.model.stop() }
        r.pasteboard.clearContents(); r.pasteboard.setString("stay", forType: .string)
        r.workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        r.workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        await settle()
        #expect(r.pasteboard.string(forType: .string) == "stay")
        r.distributed.post(name: SystemClearObserver.screenLockName, object: nil)
        #expect(await eventually { r.pasteboard.string(forType: .string) == nil })
    }

    @Test func aSwitchTurnedOffLaterRemovesItsObserver() async {
        let r = rig { $0.set(true, forKey: "clipboardAutoClearOnScreenLock") }
        r.model.start(); defer { r.model.stop() }
        r.defaults.defaults.set(false, forKey: "clipboardAutoClearOnScreenLock")
        r.model.settingsChanged()
        r.pasteboard.clearContents(); r.pasteboard.setString("stay", forType: .string)
        r.distributed.post(name: SystemClearObserver.screenLockName, object: nil)
        await settle()
        #expect(r.pasteboard.string(forType: .string) == "stay")
    }

    /// The observers deliver on the main queue: give them time to run before asserting that nothing happened.
    private func settle() async { try? await Task.sleep(for: .milliseconds(200)) }
}
