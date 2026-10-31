import Foundation

/// `notchAgentsLimitFocus`: which limit the closed island shows.
enum AgentsLimitFocus: String, CaseIterable, Identifiable, Sendable {
    case mostUsed, session, weekly

    var id: String { rawValue }
    var title: String { AgentsStrings.text(rawValue) }
}
