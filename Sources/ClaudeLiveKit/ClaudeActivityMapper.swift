import Foundation
import IslandKit
import IslandUI

/// Where the monitor posts. ActivityCenter conforms in the shell; tests use a recorder.
@MainActor
public protocol ClaudeActivitySink: AnyObject {
    func post(_ activity: IslandActivity)
    func withdraw(id: String)
}

/// ClaudeSession -> IslandActivity. Idle and unknown sessions have no activity: the island stays quiet
/// rather than claiming something it does not know.
public enum ClaudeActivityMapper {
    public static let source = "claude"

    public static func activityID(for session: ClaudeSession) -> String { "claude.\(session.id)" }

    /// French label for tooltips and VoiceOver; the wing itself only has room for symbol + folder.
    public static func label(for state: ClaudeSession.State) -> String? {
        switch state {
        case .working: "Claude travaille"
        case .waiting: "Claude attend"
        case .idle, .unknown: nil
        }
    }

    public static func activity(for session: ClaudeSession) -> IslandActivity? {
        let priority: ActivityPriority
        let leading: CompactItem
        switch session.state {
        case .waiting:
            priority = .claudeWaiting
            leading = CompactItem(symbol: "hand.raised.fill", status: .warning)
        case .working:
            priority = .claudeWorking
            leading = CompactItem(symbol: "sparkles", status: .info)
        case .idle, .unknown:
            return nil
        }
        let folder = session.folderName.isEmpty ? nil : CompactItem(symbol: "folder", text: session.folderName)
        return IslandActivity(id: activityID(for: session), source: source, priority: priority,
                              leading: leading, trailing: folder)
    }
}
