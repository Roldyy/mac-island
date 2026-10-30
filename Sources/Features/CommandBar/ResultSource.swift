import Foundation

/// A provider of candidate rows. Sources do no ranking: `ResultRanker` scores everything.
protocol ResultSource: Sendable {
    /// Matches the settings keys: "apps", "files", "calculator", "web", "commands".
    var sourceID: String { get }
    /// Slow sources (disk search) are merged in after the fast ones are already on screen.
    var isSlow: Bool { get }
    func results(for query: String) async -> [BarResult]
}

extension ResultSource {
    var isSlow: Bool { false }
}
