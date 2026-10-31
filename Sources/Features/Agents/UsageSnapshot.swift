import Foundation

struct UsageTotals: Equatable, Sendable {
    var tokens = 0
    var cost = 0.0
    var estimated = false
}

/// Everything the tab shows, computed in one pass off the main actor so switching period is instant.
struct UsageSnapshot: Equatable, Sendable {
    var summaries: [UsagePeriod: UsageSummary] = [:]
    var block: UsageBlock?
    var week = UsageTotals()
    var heatmap = UsageHeatmap()

    func summary(for period: UsagePeriod) -> UsageSummary { summaries[period] ?? UsageSummary() }

    /// Oldest instant any widget needs: the heatmap reaches back furthest (13 weeks, the 30-day window
    /// starts inside it), so take the earliest of both.
    static func windowStart(now: Date, calendar: Calendar) -> Date {
        min(UsageHeatmap.gridStart(now: now, calendar: calendar),
            UsagePeriod.month.interval(now: now, calendar: calendar).start)
    }

    static func build(_ records: [UsageRecord], now: Date, calendar: Calendar) -> UsageSnapshot {
        var snapshot = UsageSnapshot()
        for period in UsagePeriod.allCases {
            snapshot.summaries[period] = UsageAggregator.summarize(records, now: now, calendar: calendar, period: period)
        }
        snapshot.block = UsageBlocks.active(records, now: now)
        let week = snapshot.summary(for: .week)
        snapshot.week = UsageTotals(tokens: week.totalTokens, cost: week.totalCost, estimated: week.costIsEstimated)
        snapshot.heatmap = UsageHeatmap.build(records, now: now, calendar: calendar)
        return snapshot
    }
}
