import Foundation

struct HeatCell: Equatable, Identifiable, Sendable {
    var day: Date
    var tokens: Int
    /// 0 = nothing, 1...4 = share of the busiest day (quartiles of the peak).
    var level: Int
    /// A day that has not happened yet: drawn empty, never counted.
    var isFuture: Bool
    var id: Date { day }
}

/// 12 columns (weeks) x 7 rows (weekdays, first weekday of the calendar on top), the last column being
/// the current week. Pure.
struct UsageHeatmap: Equatable, Sendable {
    static let weeks = 12
    static let daysPerWeek = 7

    /// `columns[week][weekday row]`.
    var columns: [[HeatCell]] = []
    var peak = 0

    /// First day of the grid; records older than this are never needed.
    static func gridStart(now: Date, calendar: Calendar) -> Date {
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        return calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: weekStart) ?? weekStart
    }

    static func build(_ records: [UsageRecord], now: Date, calendar: Calendar) -> UsageHeatmap {
        let start = gridStart(now: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        var perDay: [Date: Int] = [:]
        for record in records where record.timestamp >= start && record.timestamp <= now {
            perDay[calendar.startOfDay(for: record.timestamp), default: 0] += record.totalTokens
        }
        let peak = perDay.values.max() ?? 0
        var columns: [[HeatCell]] = []
        for week in 0..<weeks {
            var column: [HeatCell] = []
            for row in 0..<daysPerWeek {
                let day = calendar.date(byAdding: .day, value: week * daysPerWeek + row, to: start) ?? start
                let tokens = perDay[day] ?? 0
                let future = day > today
                let level = (tokens <= 0 || peak <= 0 || future) ? 0
                    : min(4, max(1, Int((4 * Double(tokens) / Double(peak)).rounded(.up))))
                column.append(HeatCell(day: day, tokens: future ? 0 : tokens, level: level, isFuture: future))
            }
            columns.append(column)
        }
        return UsageHeatmap(columns: columns, peak: peak)
    }
}
