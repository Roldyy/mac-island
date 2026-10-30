import Foundation

/// What the Claude Code CLI running in the island terminal is doing right now.
public enum ClaudeStatus: String, Sendable, Equatable {
    case idle
    case working
    case waiting
    case done
}
