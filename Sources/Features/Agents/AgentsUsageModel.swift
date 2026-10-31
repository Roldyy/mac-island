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
    private(set) var limits = LimitsState()
    private(set) var plan: PlanTier?
    /// Bound to the picker; `persistPeriod()` writes it back.
    var period: UsagePeriod
    // Page preferences: each change is written straight back to the migrated key.
    var cardOrder: [AgentsCard] { didSet { settings.save(cardOrder: cardOrder) } }
    var hiddenCards: Set<AgentsCard> { didSet { settings.save(hiddenCards: hiddenCards) } }
    var limitDisplay: AgentsLimitDisplay { didSet { settings.save(limitDisplay: limitDisplay) } }
    var limitFocus: AgentsLimitFocus { didSet { settings.save(limitFocus: limitFocus) } }
    var dailyBudget: Double? { didSet { settings.save(dailyBudget: dailyBudget) } }

    @ObservationIgnored private let settings: AgentsSettings
    @ObservationIgnored private let sources: [any UsageSource]
    @ObservationIgnored private let limitSource: PlanLimitSource
    @ObservationIgnored private let planLoader: @Sendable () -> PlanTier?
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let clock: @Sendable () -> Date

    init(settings: AgentsSettings,
         sources: [any UsageSource] = [ClaudeUsageSource(), CodexUsageSource()],
         limitSource: PlanLimitSource = PlanLimitSource(),
         planLoader: @escaping @Sendable () -> PlanTier? = { PlanTierSource.load() },
         calendar: Calendar = UsageFormat.calendar,
         clock: @escaping @Sendable () -> Date = { Date() }) {
        self.settings = settings
        self.period = settings.period
        self.cardOrder = settings.cardOrder
        self.hiddenCards = settings.hiddenCards
        self.limitDisplay = settings.limitDisplay
        self.limitFocus = settings.limitFocus
        self.dailyBudget = settings.dailyBudget
        self.sources = sources
        self.limitSource = limitSource
        self.planLoader = planLoader
        self.calendar = calendar
        self.clock = clock
    }

    var summary: UsageSummary { snapshot.summary(for: period) }

    /// Codex data exists only once a Codex source returned records (the source is still a stub).
    var hasCodexData: Bool { (snapshot.summary(for: .month).agentTokens[.codex] ?? 0) > 0 }

    var visibleCards: [AgentsCard] {
        AgentsCardLayout.visible(order: cardOrder, hidden: hiddenCards, hasCodexData: hasCodexData)
    }

    func persistPeriod() { settings.save(period: period) }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let sources = sources, calendar = calendar, now = clock()
        let limitSource = limitSource, planLoader = planLoader
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
            return (UsageSnapshot.build(records, now: now, calendar: calendar), results, records.count,
                    limitSource.load(), planLoader())
        }.value
        snapshot = output.0
        limits = LimitsState.resolve(sample: output.3, block: output.0.block, weekTokens: output.0.week.tokens, now: now)
        plan = output.4
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
