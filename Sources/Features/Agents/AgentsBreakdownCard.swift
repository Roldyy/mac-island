import IslandUI
import SwiftUI

/// "Contribution à l’usage": per subagent, MCP server, skill, plugin and CLI binary, each row with the model mix
/// behind it written out (never colour alone). Mac Island's own card: it is not one of Vorssaint's, so it lives
/// outside `AgentsCard` (whose ids are pinned to the migrated keys).
struct AgentsBreakdownCard: View {
    let breakdowns: [BreakdownWindow: UsageBreakdown]
    @Binding var window: BreakdownWindow
    /// Rows shown per section before "+ N autres".
    static let limit = 5

    private var current: UsageBreakdown { breakdowns[window] ?? UsageBreakdown() }

    var body: some View {
        IslandCard {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                HStack(spacing: IslandSpacing.xs) {
                    Image(systemName: "chart.pie")
                        .font(.islandBodyEmphasis).foregroundStyle(IslandPalette.accent.color).accessibilityHidden(true)
                    Text("Contribution à l’usage")
                        .font(.islandBodyEmphasis).foregroundStyle(IslandPalette.textPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: IslandSpacing.s)
                    AgentsSegmentedControl(items: BreakdownWindow.allCases, selection: $window, title: \.title,
                                           label: "Période de la contribution")
                }
                Text("Estimation pondérée, comme /usage. Les parts se recoupent : une requête peut compter dans plusieurs listes.")
                    .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                if current.isEmpty {
                    Text("Aucune activité sur cette période.")
                        .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                } else {
                    section("Sous-agents", rows: current.subagents)
                    section("Serveurs MCP", rows: current.mcpServers)
                    section("Skills", rows: current.skills)
                    section("Plugins", rows: current.plugins)
                    cliSection
                    hooksSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder private func section(_ title: String, rows: [BreakdownRow]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                Text(title).font(.islandCaptionEmphasis).foregroundStyle(IslandPalette.textSecondary.color)
                    .accessibilityAddTraits(.isHeader)
                ForEach(rows.prefix(Self.limit)) { row in rowView(row) }
                if rows.count > Self.limit {
                    Text("+ \(rows.count - Self.limit) autres")
                        .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                }
            }
        }
    }

    private func rowView(_ row: BreakdownRow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: IslandSpacing.s) {
                Text(row.name).font(.islandCaptionEmphasis).foregroundStyle(IslandPalette.textPrimary.color)
                    .lineLimit(1).truncationMode(.tail).help(row.name)
                Spacer(minLength: IslandSpacing.s)
                Text(Self.percentText(row.share)).font(.islandValue)
                    .foregroundStyle(IslandPalette.textPrimary.color).fixedSize()
            }
            ModelSplitBar(models: row.models, fill: row.share).frame(height: 5)
            Text(Self.modelText(row.models))
                .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color).lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.name)
        .accessibilityValue("\(Self.percentText(row.share)), \(Self.modelText(row.models))")
    }

    /// A share that exists but rounds to zero says "< 1 %", never a "0 %" that reads as unused.
    static func percentText(_ share: Double) -> String {
        share > 0 && share < 0.005 ? "< 1\(UsageFormat.thinSpace)%" : UsageFormat.percent(share)
    }

    /// "Opus 62 · Sonnet 30 · Haiku 8" (whole percents of the row, largest first, nothing under 1 %).
    static func modelText(_ models: [BreakdownModelShare]) -> String {
        let parts = models.filter { $0.share >= 0.005 }.sorted { $0.share > $1.share }
            .map { "\($0.family.title) \(Int(($0.share * 100).rounded()))" }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    /// "1,2 s", "340 ms", "2 min 5 s".
    static func durationText(ms: Int) -> String {
        if ms < 1000 { return "\(ms) ms" }
        let seconds = Double(ms) / 1000
        if seconds < 60 { return seconds.formatted(.number.precision(.fractionLength(1)).locale(UsageFormat.locale)) + " s" }
        return "\(Int(seconds) / 60) min \(Int(seconds) % 60) s"
    }

    @ViewBuilder private var hooksSection: some View {
        let rows = current.hooks
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                Text("Hooks (exécutions)").font(.islandCaptionEmphasis)
                    .foregroundStyle(IslandPalette.textSecondary.color).accessibilityAddTraits(.isHeader)
                ForEach(rows.prefix(Self.limit)) { row in
                    HStack(spacing: IslandSpacing.s) {
                        Text(row.name).font(.islandCaptionEmphasis).foregroundStyle(IslandPalette.textPrimary.color)
                            .lineLimit(1).truncationMode(.tail).help(row.name)
                        Spacer(minLength: IslandSpacing.s)
                        Text("\(row.runs) × · \(Self.durationText(ms: row.totalMs))")
                            .font(.islandValue).foregroundStyle(IslandPalette.textSecondary.color).fixedSize()
                        if row.errors > 0 {
                            Text("\(row.errors) en échec").font(.islandCaptionEmphasis)
                                .foregroundStyle(IslandStatus.danger.color).fixedSize()
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.name)
                    .accessibilityValue("\(row.runs) exécutions, \(Self.durationText(ms: row.totalMs)), \(row.errors) en échec")
                }
                if rows.count > Self.limit {
                    Text("+ \(rows.count - Self.limit) autres")
                        .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                }
                Text("Les hooks n’utilisent pas de jetons : exécutions, durée et échecs, sans pourcentage.")
                    .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var cliSection: some View {
        let rows = current.cli
        if !rows.isEmpty {
            let most = max(rows.first?.calls ?? 1, 1)
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                Text("Commandes (appels)").font(.islandCaptionEmphasis)
                    .foregroundStyle(IslandPalette.textSecondary.color).accessibilityAddTraits(.isHeader)
                ForEach(rows.prefix(Self.limit)) { row in
                    HStack(spacing: IslandSpacing.s) {
                        Text(row.name).font(.islandCaptionEmphasis).foregroundStyle(IslandPalette.textPrimary.color)
                            .lineLimit(1).frame(minWidth: 60, alignment: .leading)
                        AgentsMeter(fill: Double(row.calls) / Double(most), marker: nil,
                                    tint: IslandPalette.accent.color, barHeight: 5)
                        Text("\(row.calls)").font(.islandValue).foregroundStyle(IslandPalette.textPrimary.color)
                            .fixedSize()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.name).accessibilityValue("\(row.calls) appels")
                }
                if rows.count > Self.limit {
                    Text("+ \(rows.count - Self.limit) autres")
                        .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                }
                Text("Les commandes n’ont pas de jetons propres : comptées, pas pondérées.")
                    .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The row's bar: its length is the row's share of all usage, split by model family inside.
private struct ModelSplitBar: View {
    let models: [BreakdownModelShare]
    let fill: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(IslandPalette.textPrimary.color.opacity(0.14))
                HStack(spacing: 0) {
                    ForEach(models.indices, id: \.self) { index in
                        Rectangle().fill(models[index].family.color)
                            .frame(width: max(0, min(1, fill)) * width * models[index].share)
                    }
                }
                .clipShape(Capsule())
            }
        }
        .accessibilityHidden(true)
    }
}

/// The extra-usage credit and where the month stands in it, from Claude Code's own cache. Age and "périmé" are
/// as large as the figure: a stale "limit not reached" must never look current.
struct AgentsExtraUsageCard: View {
    let extra: ExtraUsage
    let now: Date

    private var stale: Bool { extra.isStale(at: now) }
    private var tint: Color {
        if extra.limitReached || extra.disabledReason != nil { return IslandStatus.danger.color }
        return (extra.percent ?? 0) >= 80 ? IslandStatus.warning.color : IslandPalette.accent.color
    }

    var body: some View {
        IslandCard {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                HStack(spacing: IslandSpacing.xs) {
                    Image(systemName: "creditcard")
                        .font(.islandBodyEmphasis).foregroundStyle(tint).accessibilityHidden(true)
                    Text("Crédit supplémentaire")
                        .font(.islandBodyEmphasis).foregroundStyle(IslandPalette.textPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: IslandSpacing.s)
                    Text(stale ? "périmé · \(extra.ageText(at: now))" : "mesuré \(extra.ageText(at: now))")
                        .font(.islandCaptionEmphasis)
                        .foregroundStyle(stale ? IslandStatus.warning.color : IslandPalette.textSecondary.color)
                }
                if let status = extra.statusText {
                    Text(status).font(.islandBodyEmphasis).foregroundStyle(IslandStatus.danger.color)
                }
                if let used = extra.used, let limit = extra.limit {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Self.money(used, extra.currency)) sur \(Self.money(limit, extra.currency))")
                            .font(.islandBodyEmphasis).foregroundStyle(IslandPalette.textPrimary.color)
                        Spacer(minLength: IslandSpacing.s)
                        if let percent = extra.percent {
                            Text(UsageFormat.percent(extra.limitReached ? 1 : percent / 100)).font(.islandValue)
                                .foregroundStyle(IslandPalette.textPrimary.color)
                        }
                    }
                    AgentsMeter(fill: extra.fill, marker: nil, tint: tint, barHeight: 8)
                        .frame(height: 8)
                    if limit > used {
                        Text("Reste \(Self.money(limit - used, extra.currency)) ce mois-ci")
                            .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .opacity(stale ? 0.7 : 1)
        }
        .accessibilityElement(children: .combine)
    }

    static func money(_ value: Double, _ currency: String) -> String {
        value.formatted(.currency(code: currency).locale(UsageFormat.locale))
    }
}
