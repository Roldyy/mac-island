import Foundation

/// The three periods of the picker. Raw values are the ones the old app stored in `notchAgentsPeriod`;
/// `month` is a rolling 30 days, as the old label says.
enum UsagePeriod: String, CaseIterable, Identifiable, Sendable {
    case today, week, month

    var id: String { rawValue }

    /// Number of days the window covers (1 = today only).
    var days: Int {
        switch self {
        case .today: 1
        case .week: 7
        case .month: 30
        }
    }

    var title: String { AgentsStrings.text(rawValue) }

    /// Spoken and shown in headline captions ("tokens sur 7 jours").
    var phrase: String {
        switch self {
        case .today: "aujourd’hui"
        case .week: "sur 7 jours"
        case .month: "sur 30 jours"
        }
    }

    /// Today, or a rolling 7 / 30 days ending today (not a calendar week or month).
    func interval(now: Date, calendar: Calendar) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        if self == .today {
            return calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: today, duration: 86_400)
        }
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        let end = calendar.date(byAdding: .day, value: days, to: start) ?? now
        return DateInterval(start: start, end: end)
    }
}
