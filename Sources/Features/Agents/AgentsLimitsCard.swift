import IslandUI
import SwiftUI

struct AgentsLimitsCard: View {
    let limits: LimitsState
    let display: AgentsLimitDisplay

    var body: some View {
        AgentsCardFrame(.limits) {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                ForEach(limits.rows) { row in
                    meterRow(row)
                }
                footer
            }
        }
    }

    private func meterRow(_ row: LimitRow) -> some View {
        let value = row.valueText(display)
            ?? row.tokens.map { AgentsStrings.format("tokensFormat", UsageFormat.tokens($0)) }
        return VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title).font(.islandBody).foregroundStyle(IslandPalette.textPrimary.color)
                Spacer(minLength: IslandSpacing.xs)
                if let value {
                    Text(value).font(.islandValue).foregroundStyle(IslandPalette.textSecondary.color)
                }
            }
            AgentsMeter(fill: row.fill(display), marker: row.paceMarker(display), tint: Self.tint(row))
            if let renewal = row.renewal {
                AgentsNote("\(AgentsStrings.renewsAt) \(UsageFormat.clock(renewal))")
            }
        }
        .opacity(limits.isStale ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.title)
        .accessibilityValue([value, row.renewal.map { "\(AgentsStrings.renewsAt) \(UsageFormat.clock($0))" }]
            .compactMap { $0 }.joined(separator: ", "))
    }

    @ViewBuilder private var footer: some View {
        switch limits.source {
        case .planFile:
            if let updated = limits.updated {
                AgentsNote(AgentsStrings.format("updatedFormat", UsageFormat.relative(updated, now: Date())))
            }
        case .estimatedFromLogs:
            AgentsNote(AgentsStrings.text("estimated"))
        case .none:
            AgentsNote(AgentsStrings.text("waitingForLimits"))
        }
    }

    static func tint(_ row: LimitRow) -> Color {
        guard let used = row.usedPercent else { return IslandPalette.accent.color }
        return used >= 90 ? IslandStatus.danger.color : used >= 75 ? IslandStatus.warning.color : IslandPalette.accent.color
    }
}
