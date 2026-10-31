import IslandUI
import SwiftUI

/// One row of a share list.
struct ShareRow: Identifiable, Equatable {
    var name: String
    var tokens: Int
    var cost: Double
    var estimated: Bool
    var id: String { name }
}

/// "Modèles" and "Projets": colored dot and name (it takes every spare point), share bar, share, tokens and
/// cost in columns that size to their content, so a cost is never cut. "+ N autres" opens more rows inline.
struct AgentsShareCard: View {
    let card: AgentsCard
    let rows: [ShareRow]
    /// Half-width card: the share bar and the percentage give way to the name.
    var compact = false
    static let limit = 6
    static let step = 10
    @State private var shown = AgentsShareCard.limit

    init(card: AgentsCard, rows: [ShareRow], compact: Bool = false, expanded: Bool = false) {
        self.card = card
        self.rows = rows
        self.compact = compact
        _shown = State(initialValue: expanded ? rows.count : Self.limit)
    }

    private var total: Int { max(rows.reduce(0) { $0 + $1.tokens }, 1) }

    var body: some View {
        AgentsCardFrame(card) {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                if rows.isEmpty {
                    Text(AgentsStrings.text("noActivity")).font(.islandCaption)
                        .foregroundStyle(IslandPalette.textSecondary.color)
                } else {
                    Grid(alignment: .leading, horizontalSpacing: IslandSpacing.s, verticalSpacing: IslandSpacing.s + 2) {
                        ForEach(Array(rows.prefix(shown).enumerated()), id: \.element.id) { index, row in
                            gridRow(row, index: index)
                        }
                    }
                    more
                }
            }
        }
    }

    private func gridRow(_ row: ShareRow, index: Int) -> some View {
        let share = Double(row.tokens) / Double(total)
        let tint = tint(row, index: index)
        return GridRow {
            HStack(spacing: IslandSpacing.s) {
                Circle().fill(tint).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(card == .models ? ModelFamily.displayName(row.name) : row.name)
                    .font(.islandCaptionEmphasis).foregroundStyle(IslandPalette.textPrimary.color)
                    .lineLimit(1).truncationMode(.tail)
                    .help(row.name)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !compact {
                AgentsMeter(fill: share, marker: nil, tint: tint, barHeight: 5).frame(width: 64)
                column(UsageFormat.percent(share), primary: false)
            }
            column(UsageFormat.tokensShort(row.tokens), primary: false)
            column(UsageFormat.costShort(row.cost, estimated: row.estimated), primary: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.name)
        .accessibilityValue("\(UsageFormat.percent(share)), \(UsageFormat.exactTokens(row.tokens)) tokens, \(UsageFormat.cost(row.cost, estimated: row.estimated))")
    }

    private func column(_ text: String, primary: Bool) -> some View {
        Text(text).font(.islandValue)
            .foregroundStyle(primary ? IslandPalette.textPrimary.color : IslandPalette.textSecondary.color)
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .gridColumnAlignment(.trailing)
    }

    @ViewBuilder private var more: some View {
        let hidden = rows.count - shown
        if hidden > 0 || shown > Self.limit {
            HStack(spacing: IslandSpacing.m) {
                if hidden > 0 {
                    Button { shown = min(rows.count, shown + Self.step) } label: {
                        Label(AgentsStrings.fill(constant: AgentsStrings.moreFormat, "\(hidden)"), systemImage: "chevron.down")
                            .font(.islandCaptionEmphasis).foregroundStyle(IslandPalette.accent.color)
                    }
                }
                if shown > Self.limit {
                    Button { shown = Self.limit } label: {
                        Label(AgentsStrings.collapse, systemImage: "chevron.up")
                            .font(.islandCaptionEmphasis).foregroundStyle(IslandPalette.textSecondary.color)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.top, IslandSpacing.xxs)
        }
    }

    /// Models take their family color (the same one as the trend chart); projects cycle through the palette.
    private func tint(_ row: ShareRow, index: Int) -> Color {
        if card == .models { return ModelFamily(model: row.name).color }
        let palette = [IslandPalette.accent.color, IslandStatus.success.color, IslandStatus.warning.color, IslandStatus.info.color]
        return palette[index % palette.count]
    }
}
