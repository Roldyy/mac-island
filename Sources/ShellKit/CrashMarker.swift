import Darwin
import Foundation

/// Names the feature whose start() is running, in a small file. A crash inside start() kills the
/// process before UserDefaults flushes to disk, so the marker is written, fsynced and closed before
/// start() runs; a file still there at the next launch means that start never returned.
public struct CrashMarker: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// Best effort: a failure to write must never keep a feature from starting.
    public func begin(_ id: String) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard fd >= 0 else { return }
        defer { close(fd) }
        let bytes = Array(id.utf8)
        var written = 0
        while written < bytes.count {
            let n = bytes[written...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            guard n > 0 else { break }
            written += n
        }
        _ = fsync(fd)
    }

    /// The feature id left by a start that did not finish, if any.
    public func pending() -> String? {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8),
              !text.isEmpty else { return nil }
        return text
    }

    public func clear() { try? FileManager.default.removeItem(at: url) }

    /// `Application Support/<bundle id>/start.marker`.
    public static func standard(bundleID: String) -> CrashMarker {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return CrashMarker(url: support.appendingPathComponent(bundleID).appendingPathComponent("start.marker"))
    }
}
