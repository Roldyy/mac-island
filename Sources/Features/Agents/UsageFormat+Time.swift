import Foundation

extension UsageFormat {
    /// "14:05", fr-BE, in the calendar's time zone.
    static func clock(_ date: Date, calendar: Calendar = UsageFormat.calendar, locale: Locale = UsageFormat.locale) -> String {
        Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .format(date)
    }

    /// "il y a 2 min". A date in the future reads as "maintenant".
    static func relative(_ date: Date, now: Date, locale: Locale = UsageFormat.locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: min(date, now), relativeTo: now)
    }

    /// "21 oct." for chart tooltips and the busiest day.
    static func shortDay(_ date: Date, calendar: Calendar = UsageFormat.calendar, locale: Locale = UsageFormat.locale) -> String {
        Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .day().month(.abbreviated).format(date)
    }

    /// "9 h" for the hourly bars.
    static func hour(_ date: Date, calendar: Calendar = UsageFormat.calendar) -> String {
        "\(calendar.component(.hour, from: date)) h"
    }

    /// The plan comparison figure: "3,2×".
    static func multiple(_ value: Double, locale: Locale = UsageFormat.locale) -> String {
        value.formatted(.number.precision(.fractionLength(value >= 10 ? 0 : 1)).locale(locale)) + "×"
    }
}
