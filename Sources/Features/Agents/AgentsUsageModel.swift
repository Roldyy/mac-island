import ClaudeLiveKit
import Foundation
import IslandKit
import IslandUI
import Observation
import SwiftUI

/// Holds the usage snapshot. Parsing runs off the main thread; only finished states land here, one after the
/// other: the last known numbers first (from the disk cache), then richer ones as files finish reading.
@MainActor @Observable
final class AgentsUsageModel {
    static let shared = AgentsUsageModel(
        settings: AgentsSettings(store: AppDefaults.make() ?? .standard),
        sources: [ClaudeUsageSource(store: .default), CodexUsageSource()])

    private(set) var snapshot = UsageSnapshot()
    private(set) var status = AgentsDataStatus.loading
    /// True while a refresh runs. The page shows a quiet "Actualisation…", never a blocking spinner.
    private(set) var isRefreshing = false
    /// A first snapshot exists (possibly partial: see `coverage`).
    private(set) var hasLoaded = false
    /// Which periods the snapshot already accounts for completely (cold start only: a warm start is complete).
    private(set) var coverage = UsageCoverage.unread
    private(set) var lastFileCount = 0
    private(set) var malformedLines = 0
    private(set) var unreadableFiles = 0
    private(set) var limits = LimitsState()
    private(set) var plan: PlanTier?
    private(set) var lastRefresh: Date?
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
    /// Test override. nil in the app: the warm-up asks the shared monitor, it never reads session files itself.
    @ObservationIgnored private let sessionProbe: (@Sendable () -> Bool)?
    @ObservationIgnored private let liveSessions: @MainActor () -> [ClaudeSession]
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshIsInteractive = false
    @ObservationIgnored private var warmup: Task<Void, Never>?
    @ObservationIgnored private var visibleCount = 0

    init(settings: AgentsSettings,
         sources: [any UsageSource] = [ClaudeUsageSource(), CodexUsageSource()],
         limitSource: PlanLimitSource = PlanLimitSource(),
         planLoader: @escaping @Sendable () -> PlanTier? = { PlanTierSource.load() },
         calendar: Calendar = UsageFormat.calendar,
         clock: @escaping @Sendable () -> Date = { Date() },
         sessionProbe: (@Sendable () -> Bool)? = nil,
         liveSessions: @escaping @MainActor () -> [ClaudeSession] = { ClaudeLiveMonitor.shared.sessions }) {
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
        self.sessionProbe = sessionProbe
        self.liveSessions = liveSessions
    }

    /// The model's clock: the page draws "in 40 min" from it, so a snapshot can pin the time.
    var now: Date { clock() }

    var summary: UsageSummary { snapshot.summary(for: period) }

    /// Codex data exists only once a Codex source returned records (the source is still a stub).
    var hasCodexData: Bool { (snapshot.summary(for: .month).agentTokens[.codex] ?? 0) > 0 }

    var visibleCards: [AgentsCard] {
        AgentsCardLayout.visible(order: cardOrder, hidden: hiddenCards, hasCodexData: hasCodexData)
    }

    /// False while files that could hold records of `period` are still being read (the page shows a skeleton).
    func isComplete(_ period: UsagePeriod) -> Bool {
        hasLoaded && coverage.covers(period, now: now, calendar: calendar)
    }

    /// The 13-week heatmap and the 5-hour block need the whole window.
    var isFullyLoaded: Bool { hasLoaded && coverage.isComplete }

    func persistPeriod() { settings.save(period: period) }

    // MARK: refresh

    /// Reads what changed and publishes as it goes. Calls made while one is running join it.
    func refresh(interactive: Bool = false) async {
        if let running = refreshTask {
            await running.value
            return
        }
        refreshIsInteractive = interactive
        let task = Task<Void, Never> { [weak self] in await self?.runRefresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    /// Stops the read in flight; whatever finished stays cached, so the next refresh continues from there.
    func cancelRefresh() { refreshTask?.cancel() }

    private func runRefresh() async {
        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefresh = clock()
        }
        let sources = sources, calendar = calendar, now = clock()
        let limitSource = limitSource, planLoader = planLoader
        // Newest state wins: a consumer that is behind never queues stale snapshots.
        let (stream, continuation) = AsyncStream.makeStream(of: UsageUpdate.self, bufferingPolicy: .bufferingNewest(1))
        let worker = Task.detached(priority: .utility) {
            UsagePipeline.run(sources: sources, limitSource: limitSource, planLoader: planLoader, now: now,
                              calendar: calendar, shouldContinue: { !Task.isCancelled },
                              emit: { continuation.yield($0) })
            continuation.finish()
        }
        await withTaskCancellationHandler {
            for await update in stream { apply(update) }
        } onCancel: {
            worker.cancel()
            continuation.finish()
        }
    }

    private func apply(_ update: UsageUpdate) {
        if update.limits != limits { limits = update.limits }
        if update.plan != plan { plan = update.plan }
        guard let next = update.snapshot else { return }
        let animation = IslandMotion.animation(IslandMotion.standard, reduceMotion: SystemDisplayOptions().current.reduceMotion)
        withAnimation(animation) {
            if next != snapshot { snapshot = next }
            coverage = update.coverage
        }
        hasLoaded = true
        if update.isFinal {
            lastFileCount = update.results.reduce(0) { $0 + $1.fileCount }
            malformedLines = update.results.reduce(0) { $0 + $1.malformedLines }
            unreadableFiles = update.results.reduce(0) { $0 + $1.unreadableFiles }
            status = AgentsDataStatus.resolve(hasLoaded: true, sources: update.results, recordCount: update.recordCount)
        } else {
            status = update.recordCount > 0 ? .ready : .loading
        }
    }

    /// Injects a finished state (snapshots and previews: `.task` does not run there).
    func preload(snapshot: UsageSnapshot, limits: LimitsState, plan: PlanTier?, status: AgentsDataStatus = .ready,
                 hasLoaded: Bool = true, coverage: UsageCoverage = .complete, isRefreshing: Bool = false) {
        self.isRefreshing = isRefreshing
        self.snapshot = snapshot
        self.limits = limits
        self.plan = plan
        self.status = status
        self.hasLoaded = hasLoaded
        self.coverage = coverage
    }

    // MARK: warm-up and polling

    /// Called once at app start: one low-priority read so the first hover already has data, then a poll
    /// every `interval`, but only while the island shows this page or a Claude session is working.
    func startWarmup(every interval: Duration = .seconds(60)) {
        guard warmup == nil else { return }
        warmup = Task(priority: .utility) { [weak self] in
            await self?.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self, !Task.isCancelled else { return }
                if await self.shouldPoll() { await self.refresh() }
            }
        }
    }

    func stopWarmup() {
        warmup?.cancel()
        warmup = nil
    }

    private func shouldPoll() async -> Bool {
        if visibleCount > 0 { return true }
        if let probe = sessionProbe { return await Task.detached(priority: .utility) { probe() }.value }
        return liveSessions().contains { $0.state == .working || $0.state == .waiting }
    }

    /// The page is on screen: refresh now (joins a read in flight) and keep refreshing while it stays.
    func pageDidAppear() { visibleCount += 1 }

    /// The page left the screen. A read the page itself started is stopped; the warm-up's is left alone.
    func pageDidDisappear() {
        visibleCount = max(0, visibleCount - 1)
        if visibleCount == 0, refreshIsInteractive { cancelRefresh() }
    }

    /// Refresh now, then every `interval` seconds. Cancelled by SwiftUI when the view disappears.
    func refreshWhileVisible(every interval: Duration = .seconds(60)) async {
        while !Task.isCancelled {
            await refresh(interactive: true)
            try? await Task.sleep(for: interval)
        }
    }
}
