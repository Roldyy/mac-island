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

/// "Modèles" and "Projets": name, share of the period's tokens, tokens and cost, aligned in columns.
struct AgentsShareCard: View {
    let card: AgentsCard
    let rows: [ShareRow]
    static let limit = 6

    var body: some View {
        AgentsCardFrame(card) {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                if rows.isEmpty {
                    Text(AgentsStrings.text("noActivity")).font(.islandCaption)
                        .foregroundStyle(IslandPalette.textSecondary.color)
                }
                let total = max(rows.reduce(0) { $0 + $1.tokens }, 1)
                ForEach(rows.prefix(Self.limit)) { row in
                    let share = Double(row.tokens) / Double(total)
                    VStack(alignment: .leading, spacing: IslandSpacing.xs) {
                        HStack(alignment: .firstTextBaseline, spacing: IslandSpacing.xs) {
                            Text(card == .models ? ModelFamily.displayName(row.name) : row.name).font(.islandCaptionEmphasis)
                                .foregroundStyle(IslandPalette.textPrimary.color)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: IslandSpacing.xs)
                            column(UsageFormat.percent(share), width: 44, primary: false)
                            column(UsageFormat.tokens(row.tokens), width: 56, primary: false)
                            column(UsageFormat.cost(row.cost, estimated: row.estimated), width: 78, primary: true)
                        }
                        AgentsMeter(fill: share, marker: nil, tint: tint(row), barHeight: 5)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.name)
                    .accessibilityValue("\(UsageFormat.percent(share)), \(UsageFormat.exactTokens(row.tokens)) tokens, \(UsageFormat.cost(row.cost, estimated: row.estimated))")
                }
                if rows.count > Self.limit {
                    AgentsNote(AgentsStrings.fill(constant: AgentsStrings.moreFormat, "\(rows.count - Self.limit)"))
                }
            }
        }
    }

    private func column(_ text: String, width: CGFloat, primary: Bool) -> some View {
        Text(text).font(.islandValue)
            .foregroundStyle(primary ? IslandPalette.textPrimary.color : IslandPalette.textSecondary.color)
            .lineLimit(1)
            .frame(width: width, alignment: .trailing)
    }

    /// Models take their family color (the same one as the trend chart); projects stay on the accent.
    private func tint(_ row: ShareRow) -> Color {
        card == .models ? ModelFamily(model: row.name).color : IslandPalette.accent.color
    }
}
