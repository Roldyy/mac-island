import Foundation
import IslandKit
import Observation

/// Holds the usage snapshot. Parsing runs off the main thread; only the finished snapshot lands here.
@MainActor @Observable
final class AgentsUsageModel {
    static let shared = AgentsUsageModel(settings: AgentsSettings(store: AppDefaults.make() ?? .standard))

    private(set) var snapshot = UsageSnapshot()
    private(set) var status = AgentsDataStatus.loading
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var lastFileCount = 0
    private(set) var malformedLines = 0
    private(set) var unreadableFiles = 0
    /// Bound to the picker; `persistPeriod()` writes it back.
    var period: UsagePeriod

    @ObservationIgnored private let settings: AgentsSettings
    @ObservationIgnored private let sources: [any UsageSource]
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let clock: @Sendable () -> Date

    init(settings: AgentsSettings,
         sources: [any UsageSource] = [ClaudeUsageSource(), CodexUsageSource()],
         calendar: Calendar = UsageFormat.calendar,
         clock: @escaping @Sendable () -> Date = { Date() }) {
        self.settings = settings
        self.period = settings.period
        self.sources = sources
        self.calendar = calendar
        self.clock = clock
    }

    var summary: UsageSummary { snapshot.summary(for: period) }

    func persistPeriod() { settings.save(period: period) }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let sources = sources, calendar = calendar, now = clock()
        let output = await Task.detached(priority: .utility) {
            let since = UsageSnapshot.windowStart(now: now, calendar: calendar)
            var records: [UsageRecord] = []
            var results: [UsageLoadResult] = []
            for source in sources {
                var loaded = source.load(modifiedSince: since)
                records.append(contentsOf: loaded.records)
                loaded.records = []
                results.append(loaded)
            }
            return (UsageSnapshot.build(records, now: now, calendar: calendar), results, records.count)
        }.value
        snapshot = output.0
        lastFileCount = output.1.reduce(0) { $0 + $1.fileCount }
        malformedLines = output.1.reduce(0) { $0 + $1.malformedLines }
        unreadableFiles = output.1.reduce(0) { $0 + $1.unreadableFiles }
        hasLoaded = true
        status = AgentsDataStatus.resolve(hasLoaded: true, sources: output.1, recordCount: output.2)
    }

    /// Refresh now, then every `interval` seconds. Cancelled by SwiftUI when the view disappears.
    func refreshWhileVisible(every interval: Duration = .seconds(60)) async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: interval)
        }
    }
}
