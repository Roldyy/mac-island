import ClaudeLiveKit
import IslandUI
import SwiftUI

/// TEMPORARY layout: the data layer behind it is final, the screen is being replaced by the Vorssaint one.
struct AgentsTabView: View {
    @State private var model = AgentsUsageModel.shared
    @State private var live = AgentsLiveModel.shared

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: IslandSpacing.m) {
                Picker("Période", selection: $model.period) {
                    ForEach(UsagePeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: model.period) { model.persistPeriod() }

                content
                liveSessions
            }
            .padding(IslandSpacing.m)
        }
        .task { await model.refreshWhileVisible() }
        .onAppear { live.start() }
        .onDisappear { live.stop() }
    }

    @ViewBuilder private var content: some View {
        switch model.status {
        case .loading:
            IslandEmptyState(symbol: "hourglass", message: "Lecture de la consommation…")
        case .noSource:
            IslandEmptyState(symbol: "tray", message: "Aucun journal Claude Code trouvé sur ce Mac.")
        case .unreadable:
            IslandEmptyState(symbol: "exclamationmark.triangle", message: "Les journaux Claude Code sont illisibles.")
        case .empty:
            IslandEmptyState(symbol: "tray", message: "Aucune consommation sur les 12 dernières semaines.")
        case .ready:
            summaryCards
        }
    }

    private var summaryCards: some View {
        let s = model.summary
        let snap = model.snapshot
        return VStack(alignment: .leading, spacing: IslandSpacing.m) {
            IslandCard {
                HStack(alignment: .firstTextBaseline) {
                    figure(UsageFormat.tokens(s.totalTokens), "tokens \(model.period.phrase)")
                    Spacer()
                    figure(UsageFormat.cost(s.totalCost, estimated: s.costIsEstimated),
                           s.costIsEstimated ? "coût estimé" : "coût")
                }
            }
            IslandCard {
                if let block = snap.block {
                    IslandRow("Bloc de 5 h en cours",
                              subtitle: "Il reste \(UsageFormat.duration(block.remaining(at: Date())))") {
                        Text("\(UsageFormat.tokens(block.tokens)) · \(UsageFormat.cost(block.cost, estimated: block.estimated))")
                            .font(.islandValue)
                    }
                } else {
                    IslandRow("Bloc de 5 h en cours", subtitle: "Aucun bloc actif")
                }
                IslandRow("7 derniers jours") {
                    Text("\(UsageFormat.tokens(snap.week.tokens)) · \(UsageFormat.cost(snap.week.cost, estimated: snap.week.estimated))")
                        .font(.islandValue)
                }
            }
            DailyBarsView(days: model.period == .today ? s.perHour : s.perDay, hourly: model.period == .today)
            IslandCard {
                ForEach(s.perModel) { row in
                    IslandRow(row.model) {
                        Text("\(UsageFormat.tokens(row.tokens)) · \(UsageFormat.cost(row.cost, estimated: row.estimated))")
                            .font(.islandValue)
                    }
                }
            }
            IslandCard {
                ForEach(s.perProject.prefix(6)) { row in
                    IslandRow(row.name) {
                        Text(UsageFormat.cost(row.cost, estimated: row.estimated)).font(.islandValue)
                    }
                }
            }
            if model.unreadableFiles > 0 {
                Text("\(model.unreadableFiles) fichier(s) illisible(s) ignoré(s)")
                    .font(.islandFootnote)
                    .foregroundStyle(IslandPalette.textTertiary.color)
            }
        }
    }

    private func figure(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(IslandPalette.textPrimary.color)
            Text(caption).font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
        }
        .accessibilityElement(children: .combine)
    }

    private var liveSessions: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            IslandHeader("Sessions en direct")
            IslandCard {
                if live.sessions.isEmpty {
                    Text("Aucune session Claude Code ouverte")
                        .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                }
                ForEach(live.sessions) { session in
                    IslandRow(session.folderName.isEmpty ? "Session sans nom" : session.folderName,
                              status: Self.status(session.state)) {
                        Text(AgentsLiveModel.label(for: session.state)).font(.islandCaption)
                            .foregroundStyle(IslandPalette.textSecondary.color)
                    }
                }
            }
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
