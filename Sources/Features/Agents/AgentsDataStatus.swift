import Foundation

/// What the tab should say when there is no number to show. Pure, so the wording logic is tested.
enum AgentsDataStatus: Equatable, Sendable {
    case loading
    /// No source folder exists at all (Claude Code never ran here).
    case noSource
    /// Files exist but none could be read.
    case unreadable
    /// Readable, but nothing in the last 12 weeks.
    case empty
    case ready

    static func resolve(hasLoaded: Bool, sources: [UsageLoadResult], recordCount: Int) -> AgentsDataStatus {
        guard hasLoaded else { return .loading }
        if recordCount > 0 { return .ready }
        if !sources.isEmpty, sources.allSatisfy(\.directoryMissing) { return .noSource }
        if sources.contains(where: { $0.unreadableFiles > 0 }), sources.allSatisfy({ $0.fileCount == 0 }) { return .unreadable }
        return .empty
    }
}
