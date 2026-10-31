import ClaudeLiveKit
import IslandUI
import SwiftUI

/// The "Agents IA" page: a header with the period menu, then cards two per row (charts full width).
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
        .onAppear { if isLive { live.start() } }
        .onDisappear { if isLive { live.stop() } }
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
    }

    private var header: some View {
        @Bindable var model = model
        return HStack(spacing: IslandSpacing.s) {
            Text(AgentsStrings.text("title"))
                .font(.islandBodyEmphasis)
                .foregroundStyle(IslandPalette.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: IslandSpacing.s)
            AgentsSegmentedControl(items: UsagePeriod.allCases, selection: $model.period, title: \.title,
                                   label: AgentsStrings.periodLabel)
            Button(AgentsStrings.settingsLabel, systemImage: "gearshape") { showsSettings.toggle() }
                .labelStyle(.iconOnly)
                .buttonStyle(.island)
        }
        .onChange(of: model.period) { model.persistPeriod() }
    }

    // MARK: states

    @ViewBuilder private var content: some View {
        let cards = model.visibleCards
        if !model.hasLoaded {
            IslandEmptyState(symbol: "hourglass", message: AgentsStrings.text("loading"))
                .frame(minHeight: 150)
        } else if model.status != .ready && model.limits.source != .planFile {
            IslandEmptyState(symbol: "tray", message: AgentsStrings.text("empty"))
                .frame(minHeight: 150)
        } else if cards.isEmpty {
            IslandEmptyState(symbol: "rectangle.dashed", message: AgentsStrings.text("noCards"))
                .frame(minHeight: 150)
        } else {
            ForEach(Array(AgentsCardLayout.rows(cards).enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: IslandSpacing.m) {
                    ForEach(row) { card in
                        view(for: card).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func view(for card: AgentsCard) -> some View {
        let summary = model.summary
        switch card {
        case .limits:
            AgentsLimitsCard(limits: model.limits, display: model.limitDisplay, now: model.now)
        case .spend:
            let today = model.snapshot.summary(for: .today)
            AgentsSpendCard(summary: summary, period: model.period, plan: model.plan,
                            todayCost: today.totalCost, todayEstimated: today.costIsEstimated,
                            dailyBudget: model.dailyBudget)
        case .live:
            AgentsLiveCard(sessions: live.sessions, lastFinished: live.lastFinished, now: model.now)
        case .trend:
            AgentsTrendCard(buckets: TrendBuckets.make(summary: summary, period: model.period, now: model.now,
                                                       calendar: UsageFormat.calendar),
                            hourly: model.period == .today, estimated: summary.costIsEstimated)
        case .models:
            AgentsShareCard(card: .models, rows: summary.perModel.map {
                ShareRow(name: $0.model, tokens: $0.tokens, cost: $0.cost, estimated: $0.estimated)
            })
        case .projects:
            AgentsShareCard(card: .projects, rows: summary.perProject.map {
                ShareRow(name: $0.name, tokens: $0.tokens, cost: $0.cost, estimated: $0.estimated)
            })
        case .activity:
            AgentsActivityCard(heatmap: model.snapshot.heatmap,
                               stats: HeatmapStats.compute(model.snapshot.heatmap, now: model.now, calendar: UsageFormat.calendar))
        case .resets:
            EmptyView()   // Codex only, and the Codex source is a stub: `visibleCards` never lists it
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
