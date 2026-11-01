import AppKit
import Foundation

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
