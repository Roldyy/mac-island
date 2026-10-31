import Foundation

// Lane L4 owns this whole target. Foundation only: no AppKit, no SwiftUI.

/// What we know about one Claude Code session. Never holds prompt text: folder name only.
public struct ClaudeSession: Identifiable, Equatable, Sendable {
    public enum State: String, Sendable { case working, waiting, idle, unknown }

    public let id: String          // session id or pid, as a string
    public let pid: Int32
    public var state: State
    /// Last path component of the working directory, never the full path.
    public var folderName: String
    /// `cli`, `claude-vscode`, ... as written by Claude Code, or nil.
    public var entrypoint: String?
    /// When the state last changed, if the source says so. Hook state wins over a file only while newer.
    public var updatedAt: Date?

    public init(id: String, pid: Int32, state: State, folderName: String,
                entrypoint: String? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.pid = pid
        self.state = state
        self.folderName = folderName
        self.entrypoint = entrypoint
        self.updatedAt = updatedAt
    }
}
