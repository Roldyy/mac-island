import Darwin
import Foundation

/// Reads the per-session files `ClaudeHookRunner` writes. Same suspicion as for session files.
public struct ClaudeHookStore: Sendable {
    public static let maxFileBytes = 4 * 1024
    /// A hook file nobody refreshed for this long belongs to a session that is gone.
    public static let maxAge: TimeInterval = 7 * 24 * 3600
    public static let knownStates: Set<String> = ["working", "waiting", "idle"]

    public let directory: URL
    private let uid: uid_t

    public init(directory: URL = ClaudeHookRunner.defaultDirectory, uid: uid_t = getuid()) {
        self.directory = directory
        self.uid = uid
    }

    /// Records by sanitised session id. Unknown states, bad names and bad files are skipped; a time in the
    /// future is clamped to `now` (it must not pin the state forever); files older than `maxAge` are deleted.
    public func read(now: Date = Date()) -> [String: ClaudeHookRecord] {
        guard SafeFileRead.isTrustedDirectory(atPath: directory.path, uid: uid),
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [:] }
        let nowSeconds = now.timeIntervalSince1970
        var out: [String: ClaudeHookRecord] = [:]
        for name in names where name.hasSuffix(".json") {
            let id = String(name.dropLast(5))
            let path = directory.appendingPathComponent(name).path
            guard ClaudeText.sanitizedID(id) == id,
                  let data = SafeFileRead.data(atPath: path, maxBytes: Self.maxFileBytes, uid: uid),
                  var record = try? JSONDecoder().decode(ClaudeHookRecord.self, from: data),
                  Self.knownStates.contains(record.state), record.updatedAt.isFinite else { continue }
            if record.updatedAt < nowSeconds - Self.maxAge { _ = unlink(path); continue }
            record.updatedAt = min(record.updatedAt, nowSeconds)
            record.folderName = ClaudeText.folderName(fromCwd: record.folderName)
            out[id] = record
        }
        return out
    }
}
