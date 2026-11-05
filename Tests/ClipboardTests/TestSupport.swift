import AppKit
import Testing
import Foundation
import IslandKit
@testable import ClipboardFeature

/// Directories created by the tests, removed when the test process exits (swift-testing has
/// no global teardown). Synchronised: tests run in parallel.
private enum TempRegistry {
    nonisolated(unsafe) static var urls: [URL] = []
    static let lock = NSLock()
    nonisolated(unsafe) static var hooked = false

    static func add(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        urls.append(url)
        if !hooked {
            hooked = true
            atexit { TempRegistry.removeAll() }
        }
    }

    static func removeAll() {
        lock.lock(); defer { lock.unlock() }
        for u in urls { try? FileManager.default.removeItem(at: u) }
        urls.removeAll()
    }
}

/// Fresh temp directory per test, deleted at process exit. Synthetic data only.
func makeTempDir(_ name: String = "ClipTest") -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    TempRegistry.add(url)
    return url
}

func posix(_ url: URL) -> Int? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int
}

/// Waits for something a timer or task is going to do. Load tolerant: giving up needs BOTH `timeout` of wall clock
/// AND `minimumPolls` turns of the main actor, so a busy machine (other main-actor tests hold the thread for
/// seconds) cannot fail a test that only slept for a fixed time.
@MainActor
func eventually(timeout: TimeInterval = 10, minimumPolls: Int = 300, _ condition: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    var polls = 0
    while polls < minimumPolls || Date() < end {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
        polls += 1
    }
    return condition()
}

/// A private, uniquely named pasteboard. Never the general one.
func makePasteboard() -> NSPasteboard { NSPasteboard(name: .init(UUID().uuidString)) }

/// A throwaway defaults suite. The suite name is an absolute path in the temp directory, so its plist
/// never reaches ~/Library/Preferences, and both the domain and the file go when the handle is released.
final class TempDefaults {
    let suite: String
    let defaults: UserDefaults
    init() {
        suite = NSTemporaryDirectory() + "clip-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }
    deinit {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(atPath: suite + ".plist")
    }
}

/// `PlainPasteHotkeyService.performPlainPaste` answers on main after its lane work: this awaits the outcome.
@MainActor
func plainPaste(_ pb: NSPasteboard,
                accessibilityTrusted: @escaping () -> Bool = { false },
                postAccess: @escaping () -> Bool = { true },
                sendPaste: @escaping @MainActor () async -> PasteSendResult = { .posted },
                afterWrite: @escaping (Int) -> Void = { _ in },
                now: @escaping () -> TimeInterval = { StalePasteGuard.uptime() },
                frontPID: @escaping () -> pid_t? = { nil }) async -> PlainPasteOutcome {
    await withCheckedContinuation { continuation in
        PlainPasteHotkeyService.performPlainPaste(pasteboard: pb, accessibilityTrusted: accessibilityTrusted,
                                                  postAccess: postAccess, sendPaste: sendPaste,
                                                  afterWrite: afterWrite, now: now,
                                                  frontPID: frontPID) { continuation.resume(returning: $0) }
    }
}

/// `ClipboardModel.plainPasteTriggered`, awaited.
@MainActor
func plainPasteOutcome(_ model: ClipboardModel) async -> PlainPasteOutcome {
    await withCheckedContinuation { continuation in
        model.plainPasteTriggered { continuation.resume(returning: $0) }
    }
}

/// The watcher looks at the pasteboard on the lane: poll, then wait until every pending look has been reported.
@MainActor
func pollAndSettle(_ watcher: PasteboardWatcher) async {
    watcher.poll()
    #expect(await eventually { watcher.isIdle })
}

@MainActor
func pollAndSettle(_ model: ClipboardModel) async {
    model.pollNow()
    #expect(await eventually { model.watcherIsIdle })
}

/// Runs `work` on the pasteboard lane and returns its result. A test that reads a pasteboard the production code
/// writes on the lane must do the same: reading it from the main thread at the same time is the very race
/// (AppKit's type cache) the lane exists to prevent.
func onLane<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { continuation in
        GeneralPasteboardLane.shared.queue.async { continuation.resume(returning: work()) }
    }
}

/// `NSPasteboard` is not Sendable; the lane serialises every access, so passing it in is safe.
private struct LanePasteboard: @unchecked Sendable { let pb: NSPasteboard }

/// Writes `text` to a pasteboard the started model watches, on the lane (never beside the model's lane reads).
func laneWrite(_ pb: NSPasteboard, _ text: String, concealed: Bool = false) async {
    let box = LanePasteboard(pb: pb)
    await onLane {
        box.pb.clearContents(); box.pb.setString(text, forType: .string)
        if concealed { box.pb.setData(Data(), forType: .init("org.nspasteboard.ConcealedType")) }
    }
}

/// Reads the text of a pasteboard the started model watches, on the lane.
func laneString(_ pb: NSPasteboard) async -> String? {
    let box = LanePasteboard(pb: pb)
    return await onLane { box.pb.string(forType: .string) }
}
