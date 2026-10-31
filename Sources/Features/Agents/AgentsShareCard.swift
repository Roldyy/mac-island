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

/// "Modèles" and "Projets": name, share bar (of the period's tokens), tokens and cost.
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
                    VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
                        Text(row.name).font(.islandCaption).foregroundStyle(IslandPalette.textPrimary.color)
                            .lineLimit(1).truncationMode(.middle)
                        AgentsMeter(fill: Double(row.tokens) / Double(total), marker: nil)
                        Text("\(UsageFormat.tokens(row.tokens)) · \(UsageFormat.cost(row.cost, estimated: row.estimated))")
                            .font(.islandValue).foregroundStyle(IslandPalette.textSecondary.color)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.name)
                    .accessibilityValue("\(UsageFormat.percent(Double(row.tokens) / Double(total))), \(UsageFormat.exactTokens(row.tokens)) tokens, \(UsageFormat.cost(row.cost, estimated: row.estimated))")
                }
            }
        }
    }
}
