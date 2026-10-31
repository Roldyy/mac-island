import IslandUI
import SwiftUI

struct AgentsSpendCard: View {
    let summary: UsageSummary
    let period: UsagePeriod
    let plan: PlanTier?
    let todayCost: Double
    let todayEstimated: Bool
    let dailyBudget: Double?

    var body: some View {
        AgentsCardFrame(.spend) {
            VStack(alignment: .leading, spacing: IslandSpacing.xs) {
                VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
                    Text(UsageFormat.cost(summary.totalCost, estimated: summary.costIsEstimated))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(IslandPalette.textPrimary.color)
                    Text(AgentsStrings.text("apiValue"))
                        .font(.islandCaption)
                        .foregroundStyle(IslandPalette.textSecondary.color)
                }
                .accessibilityElement(children: .combine)
                if let plan, let multiple = plan.multiple(apiValue: summary.totalCost, days: period.days) {
                    line(AgentsStrings.format("planMultipleFormat", UsageFormat.multiple(multiple), plan.name))
                }
                line(AgentsStrings.format("tokensFormat", UsageFormat.tokens(summary.totalTokens)))
                line(AgentsStrings.format("cachedFormat", UsageFormat.tokens(summary.cacheReadTokens)))
                line(AgentsStrings.format("writtenFormat", UsageFormat.tokens(summary.outputTokens)))
                if summary.cacheSavings > 0 {
                    line(AgentsStrings.format("savedFormat", UsageFormat.cost(summary.cacheSavings, estimated: summary.costIsEstimated)))
                }
                budgetRow
                if summary.costIsEstimated { AgentsNote(AgentsStrings.text("unpriced")) }
                AgentsNote(AgentsStrings.text("valueNote"))
            }
        }
    }

    private func line(_ text: String) -> some View {
        Text(text).font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
    }

    private var budgetRow: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(AgentsStrings.text("budgetTitle")).font(.islandCaption)
                    .foregroundStyle(IslandPalette.textPrimary.color)
                Spacer(minLength: IslandSpacing.xs)
                Text(dailyBudget.map { "\(UsageFormat.cost(todayCost, estimated: todayEstimated)) / \(UsageFormat.cost($0, estimated: false))" }
                        ?? AgentsStrings.text("off"))
                    .font(.islandValue).foregroundStyle(IslandPalette.textSecondary.color)
            }
            if let dailyBudget {
                let fraction = todayCost / dailyBudget
                AgentsMeter(fill: min(1, fraction), marker: nil,
                            tint: fraction >= 1 ? IslandStatus.danger.color : IslandPalette.accent.color)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
