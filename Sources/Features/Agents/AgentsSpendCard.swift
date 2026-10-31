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
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
                    Text(UsageFormat.cost(summary.totalCost, estimated: summary.costIsEstimated))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(IslandPalette.textPrimary.color)
                    Text("\(AgentsStrings.text("apiValue")) · \(period.phrase)")
                        .font(.islandCaption)
                        .foregroundStyle(IslandPalette.textSecondary.color)
                }
                .accessibilityElement(children: .combine)
                if let plan, let multiple = plan.multiple(apiValue: summary.totalCost, days: period.days) {
                    Label(AgentsStrings.format("planMultipleFormat", UsageFormat.multiple(multiple), plan.name),
                          systemImage: "scalemass")
                        .font(.islandCaptionEmphasis)
                        .foregroundStyle(IslandPalette.textPrimary.color)
                }
                HStack(alignment: .top, spacing: IslandSpacing.s) {
                    stat(AgentsStrings.tokensLabel, UsageFormat.tokens(summary.totalTokens))
                    stat(AgentsStrings.cacheLabel, UsageFormat.tokens(summary.cacheReadTokens))
                    stat(AgentsStrings.writtenLabel, UsageFormat.tokens(summary.outputTokens))
                }
                if summary.cacheSavings > 0 {
                    Label(AgentsStrings.format("savedFormat", UsageFormat.cost(summary.cacheSavings, estimated: summary.costIsEstimated)),
                          systemImage: "leaf")
                        .font(.islandCaption)
                        .foregroundStyle(IslandStatus.success.color)
                }
                budgetRow
                if summary.costIsEstimated { AgentsNote(AgentsStrings.text("unpriced")) }
                AgentsNote(AgentsStrings.text("valueNote"))
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
            Text(value).font(.islandBodyEmphasis).monospacedDigit()
                .foregroundStyle(IslandPalette.textPrimary.color)
            Text(label).font(.islandFootnote).foregroundStyle(IslandPalette.textSecondary.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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
