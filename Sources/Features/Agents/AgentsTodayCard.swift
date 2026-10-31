import IslandUI
import SwiftUI

/// Today's cost and tokens as a big number beside an hour-by-hour sparkline. Always today, whatever the period picker says.
struct AgentsTodayCard: View {
    let summary: UsageSummary
    /// One value per hour from midnight to now.
    let hourly: [Double]
    /// False while today's files are still being read: the numbers become placeholders.
    let isReady: Bool

    var body: some View {
        HStack(alignment: .center, spacing: IslandSpacing.l) {
            VStack(alignment: .leading, spacing: IslandSpacing.xs) {
                HStack(spacing: IslandSpacing.xs) {
                    Image(systemName: "sun.max.fill").font(.islandCaption).foregroundStyle(IslandStatus.success.color)
                        .accessibilityHidden(true)
                    Text(AgentsStrings.text("today")).font(.islandBodyEmphasis).foregroundStyle(IslandPalette.textPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                }
                if isReady {
                    AgentsFigure(text: UsageFormat.cost(summary.totalCost, estimated: summary.costIsEstimated),
                                 font: .system(size: 28, weight: .bold, design: .rounded))
                    Text("\(AgentsStrings.format("tokensFormat", UsageFormat.tokens(summary.totalTokens))) · \(AgentsStrings.text("apiValue"))")
                        .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color).lineLimit(1)
                } else {
                    AgentsSkeletonBar(width: 120, height: 28)
                    AgentsSkeletonBar(width: 170, height: 11)
                }
            }
            .layoutPriority(1)
            if isReady {
                AgentsSparkline(values: hourly).frame(minWidth: 80, maxWidth: .infinity).frame(height: 46)
            } else {
                AgentsSkeletonBar(height: 46)
            }
        }
        .padding(IslandSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .islandGlass(cornerRadius: IslandRadius.medium)
        .background(LinearGradient(colors: [IslandStatus.success.color.opacity(0.10), .clear], startPoint: .topLeading, endPoint: .center)
            .clipShape(RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous)))
        .accessibilityElement(children: .combine)
    }
}
