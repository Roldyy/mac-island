import Foundation
import IslandTestSupport
import Testing
@testable import PortKit

/// Lane W4-D: "Rétablir le fond d’écran précédent", on a fake desktop, a fake file system and a fake agent restart.
/// Nothing here touches the real wallpaper, `Index.plist` or `WallpaperAgent`.
@Suite struct MediaToolsWallpaperTests {
    final class Rig {
        let defaults: UserDefaults
        let cleanup: () -> Void
        let fileSystem = FakeMediaFileSystem()
        let desktop = FakeWallpaperDesktop()
        var restarts = 0
        var restartSucceeds = true
        let indexPath = "/Library/Store/Index.plist"
        let backupPath = "/App/WallpaperIndex.bak"

        init() {
            let bench = TestDefaults.make()
            defaults = bench.defaults
            cleanup = bench.cleanup
        }

        var restorer: WallpaperRestorer {
            WallpaperRestorer(defaults: defaults, fileSystem: fileSystem, desktop: desktop, indexPath: indexPath,
                              backupPath: backupPath, restartAgent: { [self] in restarts += 1; return restartSucceeds })
        }

        func addImage(_ path: String, screen: String) {
            fileSystem.files[path] = Data("img".utf8)
            desktop.images[screen] = URL(fileURLWithPath: path)
        }

        static func plist(_ marker: String) -> Data {
            try! PropertyListSerialization.data(fromPropertyList: ["Marker": marker, "Displays": [String: String]()],
                                                format: .binary, options: 0)
        }
    }

    // MARK: Restore point

    @Test func nothingIsRememberedUntilSomethingIsChanged() {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.addImage("/Pictures/a.heic", screen: "1")
        #expect(rig.restorer.canRestore == false && rig.restorer.storedPoint == nil)
        #expect(rig.defaults.data(forKey: WallpaperRestorer.pointKey) == nil)
    }

    @Test func theFirstChangeRemembersTheImagesThatExistAndLaterChangesNeverOverwriteIt() throws {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.addImage("/Pictures/a.heic", screen: "1")
        rig.addImage("/Pictures/b.heic", screen: "2")
        rig.desktop.images["3"] = URL(fileURLWithPath: "/Pictures/deleted.heic")  // not on disk
        rig.restorer.captureIfNeeded()
        let point = try #require(rig.restorer.storedPoint)
        #expect(point.images == ["1": URL(fileURLWithPath: "/Pictures/a.heic").absoluteString,
                                 "2": URL(fileURLWithPath: "/Pictures/b.heic").absoluteString])
        #expect(rig.restorer.canRestore)
        // The desktop changes (an apply), a second capture keeps the first point.
        rig.addImage("/Pictures/new.heic", screen: "1")
        rig.restorer.captureIfNeeded()
        #expect(rig.restorer.storedPoint == point)
    }

    @Test func aDynamicOrMissingWallpaperRecordsNothing() {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.restorer.captureIfNeeded()  // no screen at all
        #expect(rig.restorer.storedPoint == nil)
        rig.desktop.images["1"] = URL(string: "https://example.com/x.heic")!  // not a file URL
        rig.restorer.captureIfNeeded()
        #expect(rig.restorer.storedPoint == nil, "only file URLs are remembered, nothing is ever fetched")
    }

    @Test func anExistingIndexCopyCountsAsSomethingToRestoreAndBlocksANewPoint() {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.fileSystem.files[rig.backupPath] = Rig.plist("original")
        rig.addImage("/Pictures/a.heic", screen: "1")
        #expect(rig.restorer.canRestore)
        rig.restorer.captureIfNeeded()
        #expect(rig.restorer.storedPoint == nil, "the copy already holds the original state")
    }

    // MARK: Restore

    @Test func restoreSetsEachRememberedImageBackAndForgetsThePoint() {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.addImage("/Pictures/a.heic", screen: "1")
        rig.addImage("/Pictures/b.heic", screen: "2")
        rig.restorer.captureIfNeeded()
        rig.addImage("/Pictures/changed.heic", screen: "1")
        rig.addImage("/Pictures/changed2.heic", screen: "2")

        let outcome = rig.restorer.restore()
        #expect(outcome.screensRestored == 2 && outcome.screensFailed == 0 && outcome.succeeded)
        #expect(outcome.index == .none && outcome.didRestoreAnything)
        #expect(rig.desktop.images["1"]?.path == "/Pictures/a.heic" && rig.desktop.images["2"]?.path == "/Pictures/b.heic")
        #expect(rig.restorer.canRestore == false, "the point is used once")
        #expect(rig.restarts == 0, "no copy of the store: the agent is left alone")
        let again = rig.restorer.restore()
        #expect(again.screensRestored == 0 && !again.didRestoreAnything && rig.desktop.setCalls.count == 2, "idempotent")
    }

    @Test func aScreenOrAnImageThatIsGoneIsSkippedNotFailed() {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.addImage("/Pictures/a.heic", screen: "1")
        rig.addImage("/Pictures/b.heic", screen: "2")
        rig.restorer.captureIfNeeded()
        rig.desktop.images["2"] = nil  // the second display was unplugged
        rig.fileSystem.files["/Pictures/a.heic"] = nil  // and the first picture was deleted
        let outcome = rig.restorer.restore()
        #expect(outcome.screensRestored == 0 && outcome.screensFailed == 0 && outcome.succeeded)
        #expect(rig.desktop.setCalls.isEmpty)
    }

    @Test func aFailingScreenIsReportedAndKeepsThePointForAnotherTry() {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.addImage("/Pictures/a.heic", screen: "1")
        rig.addImage("/Pictures/b.heic", screen: "2")
        rig.restorer.captureIfNeeded()
        rig.desktop.failingScreens = ["2"]
        let outcome = rig.restorer.restore()
        #expect(outcome.screensRestored == 1 && outcome.screensFailed == 1 && !outcome.succeeded)
        #expect(rig.restorer.canRestore, "kept")
        rig.desktop.failingScreens = []
        #expect(rig.restorer.restore().succeeded && !rig.restorer.canRestore)
    }

    @Test func theIndexCopyIsParsedWrittenAtomicallyTheAgentRestartedAndTheCopyRemoved() {
        let rig = Rig()
        defer { rig.cleanup() }
        let original = Rig.plist("original")
        rig.fileSystem.files[rig.backupPath] = original
        rig.fileSystem.files[rig.indexPath] = Rig.plist("patched")
        let outcome = rig.restorer.restore()
        #expect(outcome.index == .restored && outcome.agentRestarted && outcome.succeeded)
        #expect(rig.fileSystem.files[rig.indexPath] == original)
        #expect(rig.fileSystem.writes == [rig.indexPath], "one write, to the store")
        #expect(rig.restarts == 1)
        #expect(rig.fileSystem.files[rig.backupPath] == nil && !rig.restorer.canRestore)
    }

    @Test func aCopyThatIsNotAPropertyListIsNeverWrittenOverTheStore() {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.fileSystem.files[rig.backupPath] = Data("not a plist".utf8)
        let patched = Rig.plist("patched")
        rig.fileSystem.files[rig.indexPath] = patched
        let outcome = rig.restorer.restore()
        #expect(outcome.index == .failed && !outcome.succeeded)
        #expect(rig.fileSystem.files[rig.indexPath] == patched && rig.fileSystem.writes.isEmpty)
        #expect(rig.restarts == 0 && rig.fileSystem.files[rig.backupPath] != nil, "the copy stays for a later try")

        // A property list that is not a dictionary is refused too.
        rig.fileSystem.files[rig.backupPath] = try! PropertyListSerialization.data(fromPropertyList: ["a", "b"], format: .binary, options: 0)
        #expect(rig.restorer.restore().index == .failed)
    }

    @Test func aFailedWriteKeepsTheCopyAndDoesNotRestartTheAgent() {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.fileSystem.files[rig.backupPath] = Rig.plist("original")
        rig.fileSystem.failWrites = true
        let outcome = rig.restorer.restore()
        #expect(outcome.index == .failed && rig.restarts == 0)
        #expect(rig.fileSystem.files[rig.backupPath] != nil)
    }

    @Test func anAgentThatCouldNotBeRestartedIsFlaggedButTheStoreIsRestored() {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.fileSystem.files[rig.backupPath] = Rig.plist("original")
        rig.restartSucceeds = false
        let outcome = rig.restorer.restore()
        #expect(outcome.index == .restored && outcome.agentRestarted == false && outcome.succeeded)
        #expect(rig.restarts == 1)
    }

    @Test func noCopyMeansTheAgentIsNeverTouched() {
        let rig = Rig()
        defer { rig.cleanup() }
        let result = rig.restorer.restoreIndex()
        #expect(result.result == .none && rig.restarts == 0 && rig.fileSystem.writes.isEmpty)
    }

    // MARK: Live wiring

    @Test func theLiveRestorerPointsAtTheSystemStoreAndTheAppCopyAndOnlyKillsTheWallpaperAgent() {
        let live = WallpaperRestore.live
        #expect(live.indexPath.hasSuffix("com.apple.wallpaper/Store/Index.plist"))
        #expect(live.backupPath.hasSuffix("WallpaperIndex.vorssaint-bak"))
        #expect(!live.backupPath.contains("com.apple.wallpaper"), "the copy lives with the app, not in the system store")
        #expect(WallpaperRestorer.pointKey == "macisland.wallpaper.restorePoint")
    }
}
