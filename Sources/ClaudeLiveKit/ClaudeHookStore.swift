import Foundation

/// Reads the per-session files `ClaudeHookRunner` writes. Same suspicion as for session files.
public struct ClaudeHookStore: Sendable {
    public static let maxFileBytes = 4 * 1024

    public let directory: URL

    public init(directory: URL = ClaudeHookRunner.defaultDirectory) {
        self.directory = directory
    }

    /// Records by sanitised session id. Unknown states, bad names and bad files are skipped.
    public func read() -> [String: ClaudeHookRecord] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [:] }
        var out: [String: ClaudeHookRecord] = [:]
        for name in names where name.hasSuffix(".json") {
            let id = String(name.dropLast(5))
            guard ClaudeText.sanitizedID(id) == id,
                  let data = SafeFileRead.data(atPath: directory.appendingPathComponent(name).path,
                                               maxBytes: Self.maxFileBytes),
                  var record = try? JSONDecoder().decode(ClaudeHookRecord.self, from: data),
                  ClaudeHookStore.state(record.state) != nil, record.updatedAt.isFinite else { continue }
            record.folderName = ClaudeText.folderName(fromCwd: record.folderName)
            out[id] = record
        }
        return out
    }

    static func state(_ raw: String) -> ClaudeSession.State? {
        switch raw {
        case "working": .working
        case "waiting": .waiting
        case "idle": .idle
        default: nil
        }
    }
}

/// Session files plus hook files, merged. A hook only refines a session that is verified alive:
/// a hook file alone never makes a session appear (it carries no pid, so no liveness check).
public struct ClaudeLiveSource: Sendable {
    public let reader: ClaudeSessionReader
    public let hooks: ClaudeHookStore?

    public init(reader: ClaudeSessionReader, hooks: ClaudeHookStore? = ClaudeHookStore()) {
        self.reader = reader
        self.hooks = hooks
    }

    public func snapshot() -> [ClaudeSession] {
        Self.merge(sessions: reader.read(), hooks: hooks?.read() ?? [:])
    }

    /// Hook state wins only while newer than the session file's own update time.
    static func merge(sessions: [ClaudeSession], hooks: [String: ClaudeHookRecord]) -> [ClaudeSession] {
        sessions.map { session in
            guard let hook = hooks[session.id], let hookState = ClaudeHookStore.state(hook.state) else { return session }
            let hookTime = Date(timeIntervalSince1970: hook.updatedAt)
            if let fileTime = session.updatedAt, fileTime >= hookTime { return session }
            var merged = session
            merged.state = hookState
            merged.updatedAt = hookTime
            if merged.folderName.isEmpty { merged.folderName = hook.folderName }
            return merged
        }
    }
}
