import Foundation
import Testing
@testable import FinderFeature

final class FakeScripting: FinderScripting, @unchecked Sendable {
    private let lock = NSLock()
    var selectionResult: Result<[URL], FinderScriptError> = .success([])
    var folderResult: Result<URL, FinderScriptError> = .failure(.failed)
    func selection() async throws -> [URL] { try lock.withLock { selectionResult }.get() }
    func targetFolder() async throws -> URL { try lock.withLock { folderResult }.get() }
}

@MainActor
final class FakeEnvironment: FinderEnvironment {
    var finder = true
    var editing = false
    var editingQueries = 0
    func isFinderFrontmost() -> Bool { finder }
    func isTextEditing() -> Bool { editingQueries += 1; return editing }
}

struct FakePasteboard: PasteboardReading {
    var hasFileURLs = false
    var hasImage = false
    var png: Data? = nil
    func pngData() -> Data? { png }
}

final class Box<T>: @unchecked Sendable { var value: T; init(_ v: T) { value = v } }

@MainActor
@Suite struct FinderControllerTests {
    let t0 = Date(timeIntervalSince1970: 1_793_369_002)

    func make(_ scripting: FakeScripting, env: FakeEnvironment? = nil,
              pb: FakePasteboard = FakePasteboard(), cutOn: Bool = true, imageOn: Bool = true,
              clock: Box<Date>? = nil) -> FinderController {
        let c = clock ?? Box(t0)
        return FinderController(scripting: scripting, environment: env ?? FakeEnvironment(), pasteboard: pb,
                                settings: { (cutOn, imageOn) }, clock: { c.value }, timeZone: { .gmt })
    }
    func key(_ code: Int, command: Bool = true, rep: Bool = false) -> KeyChord {
        KeyChord(keyCode: code, command: command, shift: false, option: false, control: false, isRepeat: rep)
    }

    @Test func cutThenPasteMovesRealFiles() async throws {
        let root = makeTempDir()
        let f = touch(root.appendingPathComponent("s/a.txt"), "data")
        let dest = mkdir(root.appendingPathComponent("d"))
        let sc = FakeScripting(); sc.selectionResult = .success([f]); sc.folderResult = .success(dest)
        let c = make(sc)
        #expect(c.handleKey(key(KeyCode.x)))
        // Cut is pending immediately, even before Finder answered.
        #expect(c.decide(key(KeyCode.v)) == .swallowPasteMove)
        #expect(c.handleKey(key(KeyCode.v)))
        await c.idle()
        #expect(c.outcome == .moved(1))
        #expect(c.cutCount == 0)
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("a.txt").path))
        #expect(!FileManager.default.fileExists(atPath: f.path))
    }
    @Test func cutRecordsCountOnly() async {
        let sc = FakeScripting()
        sc.selectionResult = .success([URL(fileURLWithPath: "/a/1"), URL(fileURLWithPath: "/a/2")])
        let c = make(sc)
        _ = c.handleKey(key(KeyCode.x)); await c.idle()
        #expect(c.cutCount == 2)
        #expect(c.outcome == .cutMarked(2))
    }
    @Test func emptySelectionClearsCut() async {
        let sc = FakeScripting(); sc.selectionResult = .success([URL(fileURLWithPath: "/a/1")])
        let c = make(sc)
        _ = c.handleKey(key(KeyCode.x)); await c.idle()
        sc.selectionResult = .success([])
        _ = c.handleKey(key(KeyCode.x)); await c.idle()
        #expect(c.cutCount == 0)
        #expect(c.outcome == .nothingSelected)
    }
    @Test func escAndCopyCancelButPass() async {
        let sc = FakeScripting(); sc.selectionResult = .success([URL(fileURLWithPath: "/a/1")])
        let c = make(sc)
        _ = c.handleKey(key(KeyCode.x)); await c.idle()
        #expect(!c.handleKey(key(KeyCode.esc, command: false)))
        #expect(c.cutCount == 0)
        _ = c.handleKey(key(KeyCode.x)); await c.idle()
        #expect(!c.handleKey(key(KeyCode.c)))
        #expect(c.cutCount == 0)
    }
    @Test func cutExpires() async {
        let clock = Box(t0)
        let sc = FakeScripting(); sc.selectionResult = .success([URL(fileURLWithPath: "/a/1")])
        let c = make(sc, clock: clock)
        _ = c.handleKey(key(KeyCode.x)); await c.idle()
        clock.value = t0.addingTimeInterval(PendingCut.lifetime + 5)
        #expect(c.cutCount == 0)
        #expect(c.decide(key(KeyCode.v)) == .pass)
    }
    @Test func nothingHappensOutsideFinderOrInTextField() async {
        let env = FakeEnvironment(); env.finder = false
        let c = make(FakeScripting(), env: env)
        #expect(c.decide(key(KeyCode.x)) == .pass)
        #expect(env.editingQueries == 0)   // not even asked while another app is in front
        env.finder = true; env.editing = true
        #expect(c.decide(key(KeyCode.x)) == .pass)
    }
    @Test func otherKeysNeverQueryAccessibility() {
        let env = FakeEnvironment()
        let c = make(FakeScripting(), env: env)
        #expect(c.decide(key(0)) == .pass)
        #expect(c.decide(key(KeyCode.c)) == .pass)
        #expect(env.editingQueries == 0)
    }
    @Test func disabledSettingsPassEverything() {
        let c = make(FakeScripting(), pb: FakePasteboard(hasImage: true), cutOn: false, imageOn: false)
        #expect(c.decide(key(KeyCode.x)) == .pass)
        #expect(c.decide(key(KeyCode.v)) == .pass)
    }
    @Test func imagePasteWritesPNGInFolder() async throws {
        let dest = mkdir(makeTempDir().appendingPathComponent("d"))
        let sc = FakeScripting(); sc.folderResult = .success(dest)
        let png = Data([0x89, 0x50, 0x4E, 0x47, 9])
        let c = make(sc, pb: FakePasteboard(hasImage: true, png: png))
        #expect(c.handleKey(key(KeyCode.v)))
        await c.idle()
        #expect(c.outcome == .imageSaved)
        let names = try FileManager.default.contentsOfDirectory(atPath: dest.path)
        #expect(names == ["Image 2026-10-30 at 14.03.22.png"])
    }
    @Test func filesOnPasteboardLeaveCmdVAlone() {
        let c = make(FakeScripting(), pb: FakePasteboard(hasFileURLs: true, hasImage: true))
        #expect(c.decide(key(KeyCode.v)) == .pass)
    }
    @Test func automationDeniedIsReported() async {
        let sc = FakeScripting(); sc.selectionResult = .failure(.notPermitted)
        let c = make(sc)
        _ = c.handleKey(key(KeyCode.x)); await c.idle()
        #expect(c.outcome == .automationDenied)
        #expect(c.cutCount == 0)
    }
    @Test func moveIntoItselfRefusedAndCutKept() async {
        let root = makeTempDir()
        let dir = mkdir(root.appendingPathComponent("a"))
        let inner = mkdir(dir.appendingPathComponent("in"))
        let sc = FakeScripting(); sc.selectionResult = .success([dir]); sc.folderResult = .success(inner)
        let c = make(sc)
        _ = c.handleKey(key(KeyCode.x)); await c.idle()
        _ = c.handleKey(key(KeyCode.v)); await c.idle()
        #expect(c.outcome == .refused(.intoItself))
        #expect(c.cutCount == 1)
        #expect(FileManager.default.fileExists(atPath: dir.path))
    }
    @Test func samefolderRefusedAndClears() async {
        let root = makeTempDir()
        let f = touch(root.appendingPathComponent("a.txt"))
        let sc = FakeScripting(); sc.selectionResult = .success([f]); sc.folderResult = .success(root)
        let c = make(sc)
        _ = c.handleKey(key(KeyCode.x)); await c.idle()
        _ = c.handleKey(key(KeyCode.v)); await c.idle()
        #expect(c.outcome == .refused(.sameFolder))
        #expect(FileManager.default.fileExists(atPath: f.path))
    }
    @Test func missingDestinationRefused() async {
        let root = makeTempDir()
        let f = touch(root.appendingPathComponent("s/a.txt"))
        let sc = FakeScripting(); sc.selectionResult = .success([f])
        sc.folderResult = .success(root.appendingPathComponent("gone"))
        let c = make(sc)
        _ = c.handleKey(key(KeyCode.x)); await c.idle()
        _ = c.handleKey(key(KeyCode.v)); await c.idle()
        #expect(c.outcome == .refused(.destinationUnavailable))
        #expect(FileManager.default.fileExists(atPath: f.path))
    }
    @Test func largeBatchNeedsConfirmationThenRuns() async {
        let root = makeTempDir()
        let dest = mkdir(root.appendingPathComponent("d"))
        let items = (0...MovePlanner.maxItems).map { touch(root.appendingPathComponent("s/f\($0).txt")) }
        let sc = FakeScripting(); sc.selectionResult = .success(items); sc.folderResult = .success(dest)
        let c = make(sc)
        _ = c.handleKey(key(KeyCode.x)); await c.idle()
        _ = c.handleKey(key(KeyCode.v)); await c.idle()
        #expect(c.outcome == .refused(.needsConfirmation(count: items.count)))
        #expect(c.awaitingConfirmation != nil)
        #expect(FileManager.default.fileExists(atPath: items[0].path))
        c.confirmLargeMove(); await c.idle()
        #expect(c.outcome == .moved(items.count))
        #expect(!FileManager.default.fileExists(atPath: items[0].path))
    }
    @Test func partialFailureKeepsFailedItemsCut() async {
        let root = makeTempDir()
        let ok = touch(root.appendingPathComponent("s/ok.txt"))
        let ghost = root.appendingPathComponent("s/ghost.txt")
        let dest = mkdir(root.appendingPathComponent("d"))
        let sc = FakeScripting(); sc.selectionResult = .success([ok, ghost]); sc.folderResult = .success(dest)
        let c = make(sc)
        _ = c.handleKey(key(KeyCode.x)); await c.idle()
        _ = c.handleKey(key(KeyCode.v)); await c.idle()
        #expect(c.outcome == .movedPartial(moved: 1, failed: 1))
        #expect(c.cutCount == 1)
    }
    @Test func statusLines() {
        #expect(FinderStatusText.outcome(.movedPartial(moved: 2, failed: 1)).contains("1 en échec"))
        #expect(FinderStatusText.outcome(nil).isEmpty)
        #expect(FinderStatusText.permissions(accessibility: false, inputMonitoring: false, tapRunning: false, enabled: true).contains("Accessibilité"))
        #expect(FinderStatusText.permissions(accessibility: true, inputMonitoring: true, tapRunning: true, enabled: true).contains("actifs"))
        #expect(FinderStatusText.automation(.denied).contains("refusée"))
    }
}
