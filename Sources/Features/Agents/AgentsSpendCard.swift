import IslandUI
import SwiftUI

/// The period's cost as the headline, a sparkline of it beside, three stat chips, then the plan comparison,
/// the cache saving and the daily budget.
struct AgentsSpendCard: View {
    let summary: UsageSummary
    let period: UsagePeriod
    let plan: PlanTier?
    let todayCost: Double
    let todayEstimated: Bool
    let dailyBudget: Double?
    /// One value per bucket of the period (cost), for the sparkline.
    var series: [Double] = []

    var body: some View {
        AgentsCardFrame(.spend) {
            VStack(alignment: .leading, spacing: IslandSpacing.m) {
                headline
                HStack(alignment: .top, spacing: IslandSpacing.s) {
                    AgentsStatTile(value: UsageFormat.tokens(summary.totalTokens), label: AgentsStrings.tokensLabel, symbol: "number")
                    AgentsStatTile(value: UsageFormat.tokens(summary.cacheReadTokens), label: AgentsStrings.cacheLabel, symbol: "memorychip")
                    AgentsStatTile(value: UsageFormat.tokens(summary.outputTokens), label: AgentsStrings.writtenLabel, symbol: "pencil.line")
                }
                badges
                budgetRow
                if summary.costIsEstimated { AgentsNote(AgentsStrings.text("unpriced")) }
                AgentsNote(AgentsStrings.text("valueNote"))
            }
        }
    }

    private var headline: some View {
        HStack(alignment: .bottom, spacing: IslandSpacing.l) {
            VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
                AgentsFigure(text: UsageFormat.cost(summary.totalCost, estimated: summary.costIsEstimated),
                             font: .system(size: 34, weight: .bold, design: .rounded))
                Text("\(AgentsStrings.text("apiValue")) · \(period.phrase)")
                    .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color).lineLimit(1)
            }
            .layoutPriority(1)
            .accessibilityElement(children: .combine)
            AgentsSparkline(values: series, tint: IslandStatus.success.color)
                .frame(minWidth: 60, maxWidth: .infinity).frame(height: 44)
        }
    }

    @ViewBuilder private var badges: some View {
        let multiple = plan.flatMap { plan in plan.multiple(apiValue: summary.totalCost, days: period.days).map { (plan, $0) } }
        if multiple != nil || summary.cacheSavings > 0 {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: IslandSpacing.s) { badgeContent(multiple) }
                VStack(alignment: .leading, spacing: IslandSpacing.xs) { badgeContent(multiple) }
            }
        }
    }

    @ViewBuilder private func badgeContent(_ multiple: (PlanTier, Double)?) -> some View {
        if let (plan, value) = multiple {
            AgentsPill(text: AgentsStrings.format("planMultipleFormat", UsageFormat.multiple(value), plan.name),
                       symbol: "scalemass", tint: IslandPalette.accent.color)
        }
        if summary.cacheSavings > 0 {
            AgentsPill(text: AgentsStrings.format("savedFormat", UsageFormat.costShort(summary.cacheSavings, estimated: summary.costIsEstimated)),
                       symbol: "leaf", tint: IslandStatus.success.color)
        }
    }

    private var budgetRow: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(AgentsStrings.text("budgetTitle")).font(.islandCaption)
                    .foregroundStyle(IslandPalette.textPrimary.color).lineLimit(1)
                Spacer(minLength: IslandSpacing.xs)
                Text(dailyBudget.map { "\(UsageFormat.cost(todayCost, estimated: todayEstimated)) / \(UsageFormat.cost($0, estimated: false))" }
                        ?? AgentsStrings.text("off"))
                    .font(.islandValue).foregroundStyle(IslandPalette.textSecondary.color).lineLimit(1)
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
