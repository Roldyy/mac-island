import IslandUI
import SwiftUI

/// Today's cost and tokens as big numbers over an hour-by-hour sparkline. Always today, whatever the period picker says.
struct AgentsTodayCard: View {
    let summary: UsageSummary
    /// One value per hour from midnight to now.
    let hourly: [Double]
    /// False while today's files are still being read: the numbers become placeholders.
    let isReady: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            HStack(spacing: IslandSpacing.xs) {
                Image(systemName: "sun.max.fill").font(.islandCaption).foregroundStyle(IslandStatus.success.color)
                    .accessibilityHidden(true)
                Text(AgentsStrings.text("today")).font(.islandBodyEmphasis).foregroundStyle(IslandPalette.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
            }
            if isReady {
                AgentsFigure(text: UsageFormat.cost(summary.totalCost, estimated: summary.costIsEstimated))
                Text("\(AgentsStrings.format("tokensFormat", UsageFormat.tokens(summary.totalTokens))) · \(AgentsStrings.text("apiValue"))")
                    .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color).lineLimit(1)
                    .minimumScaleFactor(0.85)
                AgentsSparkline(values: hourly).frame(height: 34).padding(.top, IslandSpacing.xs)
            } else {
                AgentsSkeletonBar(width: 110, height: 28)
                AgentsSkeletonBar(width: 150, height: 11)
                AgentsSkeletonBar(height: 34).padding(.top, IslandSpacing.xs)
            }
        }
        .padding(IslandSpacing.m)
        .frame(maxWidth: .infinity, minHeight: 140, maxHeight: .infinity, alignment: .topLeading)
        .islandGlass(cornerRadius: IslandRadius.medium)
        .accessibilityElement(children: .combine)
    }
}
