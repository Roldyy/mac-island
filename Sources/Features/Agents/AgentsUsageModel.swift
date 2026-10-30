import Foundation
import Observation

/// Holds the month summary. Parsing runs off the main thread; only the finished summary lands here.
@MainActor @Observable
final class AgentsUsageModel {
    static let shared = AgentsUsageModel()

    private(set) var summary = UsageSummary()
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var lastFileCount = 0

    @ObservationIgnored private let sources: [any UsageSource]
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let clock: @Sendable () -> Date

    init(sources: [any UsageSource] = [ClaudeUsageSource(), CodexUsageSource()],
         calendar: Calendar = .current,
         clock: @escaping @Sendable () -> Date = { Date() }) {
        self.sources = sources
        self.calendar = calendar
        self.clock = clock
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let sources = sources, calendar = calendar, now = clock()
        let (result, files) = await Task.detached(priority: .utility) {
            let since = UsageAggregator.monthStart(containing: now, calendar: calendar)
            var records: [UsageRecord] = []
            var files = 0
            for source in sources {
                let loaded = source.load(modifiedSince: since)
                records.append(contentsOf: loaded.records)
                files += loaded.fileCount
            }
            return (UsageAggregator.summarize(records, now: now, calendar: calendar), files)
        }.value
        summary = result
        lastFileCount = files
        hasLoaded = true
    }

    /// Refresh now, then every `interval` seconds. Cancelled by SwiftUI when the view disappears.
    func refreshWhileVisible(every interval: Duration = .seconds(60)) async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: interval)
        }
    }
}
