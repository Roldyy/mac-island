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
        for u in urls {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: u.path)
            try? FileManager.default.removeItem(at: u)
        }
        urls.removeAll()
    }
}

/// Fresh temp directory per test, deleted at process exit. Synthetic data only.
func makeTempDir(_ name: String = "ShelfTest") -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    TempRegistry.add(url)
    return url
}

@discardableResult
func makeFile(_ name: String, in dir: URL, bytes: Int = 4) -> URL {
    let url = dir.appendingPathComponent(name)
    FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 0x41, count: bytes))
    return url
}

func setModified(_ url: URL, _ date: Date) {
    try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
}

func posix(_ url: URL) -> Int? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int
}

final class TempDefaults {
    let suite: String
    let defaults: UserDefaults
    init() {
        suite = "shelf-test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }
    deinit { defaults.removePersistentDomain(forName: suite) }
}
