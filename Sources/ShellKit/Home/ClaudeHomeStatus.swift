import IslandKit

/// What the Claude shortcut of the home says about the Claude Code sessions, read from the closed island's
/// wing (the activity engine already decides which one wins). Pure, so it is testable without a view.
public enum ClaudeHomeStatus: Equatable, Sendable {
    case idle, working, waiting

    public static func from(layout: ActivityLayout) -> ClaudeHomeStatus {
        guard ClaudeWing.isClaudeWing(layout.leading), let item = layout.leading else { return .idle }
        return item.status == .warning ? .waiting : .working
    }

    /// French line for the tooltip and VoiceOver; nil while idle.
    public var label: String? {
        switch self {
        case .idle: nil
        case .working: "Claude travaille"
        case .waiting: "Claude attend"
        }
    }
}
