import Foundation

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
func makeTempDir(_ name: String = "FinderTest") -> URL {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    TempRegistry.add(base)
    // Resolve /var -> /private/var so path comparisons match the real inspector.
    return base.resolvingSymlinksInPath()
}

@discardableResult
func touch(_ url: URL, _ text: String = "x") -> URL {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: url.path, contents: Data(text.utf8))
    return url
}

func mkdir(_ url: URL) -> URL {
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A throwaway defaults suite whose persistent domain is removed when the handle is released.
final class TempDefaults {
    let suite: String
    let defaults: UserDefaults
    init() {
        suite = "finder-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }
    deinit { defaults.removePersistentDomain(forName: suite) }
}
