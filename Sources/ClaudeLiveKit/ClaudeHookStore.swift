import Foundation
@_exported import ClaudeHookCore

extension ClaudeHookStore {
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
        Self.merge(sessions: reader.read(), hooks: hooks?.read(now: reader.clock()) ?? [:])
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
