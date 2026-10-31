import Foundation

/// The bars of the "Tendance" chart with the empty ones filled in, so a quiet day is a gap, not a missing bar.
enum TrendBuckets {
    /// Today: every hour from midnight to the current one. Otherwise: every day of the window up to today.
    static func make(summary: UsageSummary, period: UsagePeriod, now: Date, calendar: Calendar) -> [DayUsage] {
        let hourly = period == .today
        let source = Dictionary(uniqueKeysWithValues: (hourly ? summary.perHour : summary.perDay).map { ($0.day, $0) })
        let today = calendar.startOfDay(for: now)
        var starts: [Date] = []
        if hourly {
            let current = calendar.component(.hour, from: now)
            starts = (0...current).compactMap { calendar.date(byAdding: .hour, value: $0, to: today) }
        } else {
            starts = (0..<period.days).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        }
        return starts.map { source[$0] ?? DayUsage(day: $0, tokens: 0, cost: 0) }
    }
}
