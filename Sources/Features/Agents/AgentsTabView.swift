import ClaudeLiveKit
import IslandUI
import SwiftUI

/// The "Agents IA" page: a header with the period menu, then cards two per row (charts full width).
struct AgentsTabView: View {
    @State private var model = AgentsUsageModel.shared
    @State private var live = AgentsLiveModel.shared
    @State private var showsSettings = false

    var body: some View {
        ScrollView {
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
        .task { await model.refreshWhileVisible() }
        .onAppear { live.start() }
        .onDisappear { live.stop() }
        .onChange(of: live.sessions) { live.observe() }
    }

    private var header: some View {
        @Bindable var model = model
        return HStack(spacing: IslandSpacing.s) {
            Text(AgentsStrings.text("title"))
                .font(.islandBodyEmphasis)
                .foregroundStyle(IslandPalette.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: IslandSpacing.s)
            Menu {
                Picker(AgentsStrings.periodLabel, selection: $model.period) {
                    ForEach(UsagePeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Text(model.period.title).font(.islandCaptionEmphasis)
            }
            .menuStyle(.button)
            .buttonStyle(.island)
            .fixedSize()
            .accessibilityLabel(AgentsStrings.periodLabel)
            .accessibilityValue(model.period.title)
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
        } else if model.status != .ready && model.limits.source != .planFile {
            IslandEmptyState(symbol: "tray", message: AgentsStrings.text("empty"))
        } else if cards.isEmpty {
            IslandEmptyState(symbol: "rectangle.dashed", message: AgentsStrings.text("noCards"))
        } else {
            ForEach(Array(AgentsCardLayout.rows(cards).enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: IslandSpacing.m) {
                    ForEach(row) { card in
                        view(for: card).frame(maxWidth: .infinity, alignment: .top)
                    }
                }
            }
        }
    }

    @ViewBuilder private func view(for card: AgentsCard) -> some View {
        let summary = model.summary
        switch card {
        case .limits:
            AgentsLimitsCard(limits: model.limits, display: model.limitDisplay)
        case .spend:
            let today = model.snapshot.summary(for: .today)
            AgentsSpendCard(summary: summary, period: model.period, plan: model.plan,
                            todayCost: today.totalCost, todayEstimated: today.costIsEstimated,
                            dailyBudget: model.dailyBudget)
        case .live:
            AgentsLiveCard(sessions: live.sessions, lastFinished: live.lastFinished)
        case .trend:
            AgentsTrendCard(buckets: TrendBuckets.make(summary: summary, period: model.period, now: Date(),
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
                               stats: HeatmapStats.compute(model.snapshot.heatmap, now: Date(), calendar: UsageFormat.calendar))
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
