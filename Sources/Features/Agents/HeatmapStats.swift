import Foundation

/// The three numbers under the heatmap. Pure.
struct HeatmapStats: Equatable, Sendable {
    var streak = 0
    var activeDays = 0
    var busiest: HeatCell?

    /// Streak = consecutive active days ending today; a quiet today does not break it (the day is not over),
    /// so counting then starts from yesterday.
    static func compute(_ map: UsageHeatmap, now: Date, calendar: Calendar) -> HeatmapStats {
        let cells = map.columns.flatMap { $0 }.filter { !$0.isFuture }.sorted { $0.day < $1.day }
        var stats = HeatmapStats()
        stats.activeDays = cells.filter { $0.tokens > 0 }.count
        stats.busiest = cells.filter { $0.tokens > 0 }.max { ($0.tokens, $0.day) < ($1.tokens, $1.day) }
        var expected = calendar.startOfDay(for: now)
        var reversed = Array(cells.reversed())
        if let first = reversed.first, first.day == expected, first.tokens == 0 {
            expected = calendar.date(byAdding: .day, value: -1, to: expected) ?? expected
            reversed.removeFirst()
        }
        for cell in reversed {
            guard cell.day == expected, cell.tokens > 0 else { break }
            stats.streak += 1
            expected = calendar.date(byAdding: .day, value: -1, to: expected) ?? expected
        }
        return stats
    }
}
