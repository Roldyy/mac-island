import Foundation

/// Foundation-only core of the Claude hook: nothing here may import AppKit, SwiftUI or IslandKit,
/// because Claude Code launches the hook executable on every prompt.
public enum ClaudeHookCore {}
