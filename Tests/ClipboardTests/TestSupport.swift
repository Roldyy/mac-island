import Foundation

/// Fresh temp directory per test. Synthetic data only.
func makeTempDir(_ name: String = "ClipTest") -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func posix(_ url: URL) -> Int? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int
}
