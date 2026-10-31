import Foundation

/// `notchAgentsLimitDisplay`: show what is left or what is used.
enum AgentsLimitDisplay: String, CaseIterable, Identifiable, Sendable {
    case remaining, used

    var id: String { rawValue }
    var title: String { AgentsStrings.text(rawValue) }
}
