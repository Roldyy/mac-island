import Foundation

/// The three periods of the picker. Raw values are the ones the old app stored in `notchAgentsPeriod`.
enum UsagePeriod: String, CaseIterable, Identifiable, Sendable {
    case today, week, month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Aujourd’hui"
        case .week: "7 jours"
        case .month: "Mois"
        }
    }

    /// Spoken and shown in headline captions ("tokens sur 7 jours").
    var phrase: String {
        switch self {
        case .today: "aujourd’hui"
        case .week: "sur 7 jours"
        case .month: "ce mois-ci"
        }
    }

    /// Today, a rolling 7 days ending today (not a calendar week), or the calendar month.
    func interval(now: Date, calendar: Calendar) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .today:
            return calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: today, duration: 86_400)
        case .week:
            let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? now
            return DateInterval(start: start, end: end)
        case .month:
            return calendar.dateInterval(of: .month, for: now) ?? DateInterval(start: today, duration: 86_400)
        }
    }
}
