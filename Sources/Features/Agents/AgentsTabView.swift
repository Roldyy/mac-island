import ClaudeLiveKit
import IslandUI
import SwiftUI

/// The "Agents IA" page: a glanceable first screen (session ring, week ring, today, live sessions), then
/// the cards of the chosen period two per row (charts full width).
struct AgentsTabView: View {
    var body: some View {
        AgentsPage(model: .shared, live: .shared)
    }
}

/// The page itself, over injected models so a snapshot can feed it a finished state.
struct AgentsPage: View {
    let model: AgentsUsageModel
    let live: AgentsLiveModel
    /// Off in snapshots: `.task` / `.onAppear` do not run there and nothing may start polling.
    var isLive = true
    @State private var showsSettings: Bool
    /// Width of the page content; the island page is 540 pt, so that is the starting assumption.
    @State private var pageWidth: CGFloat = 540

    init(model: AgentsUsageModel, live: AgentsLiveModel, showsSettings: Bool = false, isLive: Bool = true) {
        self.model = model
        self.live = live
        self.isLive = isLive
        _showsSettings = State(initialValue: showsSettings)
    }

    var body: some View {
        ScrollView {
            page
        }
        .scrollIndicators(.visible)
        .task { if isLive { await model.refreshWhileVisible() } }
        .onAppear {
            if isLive {
                model.pageDidAppear()
                live.start()
            }
        }
        .onDisappear {
            if isLive {
                model.pageDidDisappear()
                live.stop()
            }
        }
        .onChange(of: live.sessions) { live.observe() }
    }

    /// Everything the scroll view holds (snapshots render it at its full height).
    var page: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.m) {
            header
            if showsSettings {
                AgentsSettingsPanel(model: model) { showsSettings = false }
            } else {
                content
            }
        }
        .padding(IslandSpacing.m)
        .onGeometryChange(for: CGFloat.self) { $0.size.width - 2 * IslandSpacing.m } action: { pageWidth = $0 }
    }

    private var header: some View {
        @Bindable var model = model
        return HStack(spacing: IslandSpacing.s) {
            Text(AgentsStrings.text("title"))
                .font(.islandBodyEmphasis)
                .foregroundStyle(IslandPalette.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            if model.isRefreshing { AgentsRefreshIndicator().transition(.opacity) }
            Spacer(minLength: IslandSpacing.s)
            AgentsSegmentedControl(items: UsagePeriod.allCases, selection: $model.period, title: \.title,
                                   label: AgentsStrings.periodLabel)
            Button(AgentsStrings.settingsLabel, systemImage: "gearshape") { showsSettings.toggle() }
                .labelStyle(.iconOnly)
                .buttonStyle(.island)
        }
        .islandAnimation(value: model.isRefreshing)
        .onChange(of: model.period) { model.persistPeriod() }
    }

    // MARK: states

    @ViewBuilder private var content: some View {
        let cards = model.visibleCards
        if model.hasLoaded, model.status != .ready, model.status != .loading, model.limits.source != .planFile {
            IslandEmptyState(symbol: "tray", message: AgentsStrings.text("empty"))
                .frame(minHeight: 150)
        } else if cards.isEmpty {
            IslandEmptyState(symbol: "rectangle.dashed", message: AgentsStrings.text("noCards"))
                .frame(minHeight: 150)
        } else {
            glance(cards)
            let lower = cards.filter { $0 != .limits && $0 != .live }
            ForEach(Array(AgentsCardLayout.rows(lower, width: pageWidth).enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: IslandSpacing.m) {
                    ForEach(row) { card in
                        view(for: card, paired: row.count > 1).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The first screen: the limits rings, today under them, live sessions last. Each part follows its
    /// card's visibility in the page settings.
    @ViewBuilder private func glance(_ cards: [AgentsCard]) -> some View {
        if cards.contains(.limits) {
            AgentsHeroCard(limits: model.limits, display: model.limitDisplay, now: model.now,
                           isLoaded: model.hasLoaded, ticking: isLive)
        }
        if cards.contains(.spend) {
            let today = model.snapshot.summary(for: .today)
            AgentsTodayCard(summary: today, hourly: Self.hourlyTokens(today, model: model),
                            isReady: model.isComplete(.today))
        }
        if cards.contains(.live) {
            AgentsSessionChips(sessions: live.sessions, lastFinished: live.lastFinished)
        }
    }

    /// Tokens per hour from midnight to now (zeros for quiet hours).
    static func hourlyTokens(_ today: UsageSummary, model: AgentsUsageModel) -> [Double] {
        TrendBuckets.make(summary: today, period: .today, now: model.now, calendar: UsageFormat.calendar).map { Double($0.tokens) }
    }

    @ViewBuilder private func view(for card: AgentsCard, paired: Bool) -> some View {
        let summary = model.summary
        let isPending = card == .activity ? !model.isFullyLoaded : !model.isComplete(model.period)
        Group {
            if isPending, card != .limits, card != .live, card != .resets {
                AgentsSkeletonCard(card: card).transition(.opacity)
            } else {
                loaded(card, summary: summary, paired: paired).transition(.opacity)
            }
        }
        .islandAnimation(.easeOut(duration: 0.3), value: isPending)
    }

    @ViewBuilder private func loaded(_ card: AgentsCard, summary: UsageSummary, paired: Bool) -> some View {
        switch card {
        case .spend:
            let today = model.snapshot.summary(for: .today)
            AgentsSpendCard(summary: summary, period: model.period, plan: model.plan,
                            todayCost: today.totalCost, todayEstimated: today.costIsEstimated,
                            dailyBudget: model.dailyBudget,
                            series: TrendBuckets.make(summary: summary, period: model.period, now: model.now,
                                                      calendar: UsageFormat.calendar).map(\.cost))
        case .trend:
            AgentsTrendCard(buckets: TrendBuckets.make(summary: summary, period: model.period, now: model.now,
                                                       calendar: UsageFormat.calendar),
                            hourly: model.period == .today, estimated: summary.costIsEstimated)
        case .models:
            AgentsShareCard(card: .models, rows: summary.perModel.map {
                ShareRow(name: $0.model, tokens: $0.tokens, cost: $0.cost, estimated: $0.estimated)
            }, compact: paired)
        case .projects:
            AgentsShareCard(card: .projects, rows: summary.perProject.map {
                ShareRow(name: $0.name, tokens: $0.tokens, cost: $0.cost, estimated: $0.estimated)
            }, compact: paired)
        case .activity:
            AgentsActivityCard(heatmap: model.snapshot.heatmap,
                               stats: HeatmapStats.compute(model.snapshot.heatmap, now: model.now, calendar: UsageFormat.calendar))
        case .limits, .live, .resets:
            EmptyView()   // limits and live sessions are the first screen; resets is Codex only (a stub: never listed)
        }
    }

    static func status(_ state: ClaudeSession.State) -> IslandStatus {
        switch state {
        case .working: .info
        case .waiting: .warning
        case .idle, .unknown: .neutral
        }
    }
}
