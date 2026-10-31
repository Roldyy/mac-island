import Foundation

/// fr-BE number formatting. A `locale` parameter keeps every function testable and deterministic.
enum UsageFormat {
    static let locale = Locale(identifier: "fr_BE")
    /// The system calendar with the Belgian French week (Monday first) for the heatmap rows.
    static var calendar: Calendar {
        var c = Calendar.current
        c.locale = locale
        return c
    }
    /// Narrow no-break space, the French typography before % and between a number and its unit.
    static let thinSpace = "\u{202F}"

    static func tokens(_ n: Int, locale: Locale = UsageFormat.locale) -> String {
        func compact(_ value: Double, _ unit: String) -> String {
            value.formatted(.number.precision(.fractionLength(1)).locale(locale)) + thinSpace + unit
        }
        switch n {
        case 1_000_000_000...: return compact(Double(n) / 1e9, "Md")
        case 1_000_000...: return compact(Double(n) / 1e6, "M")
        case 1_000...: return compact(Double(n) / 1e3, "k")
        default: return n.formatted(.number.locale(locale))
        }
    }

    /// Full number with the locale's grouping, for VoiceOver and exact values.
    static func exactTokens(_ n: Int, locale: Locale = UsageFormat.locale) -> String {
        n.formatted(.number.locale(locale))
    }

    static func cost(_ value: Double, estimated: Bool, locale: Locale = UsageFormat.locale) -> String {
        (estimated ? "~" : "") + value.formatted(.currency(code: "USD").precision(.fractionLength(2)).locale(locale))
    }

    /// `0.42` -> "42 %" with U+202F before the sign.
    static func percent(_ fraction: Double, locale: Locale = UsageFormat.locale) -> String {
        (fraction * 100).rounded().formatted(.number.precision(.fractionLength(0)).locale(locale)) + thinSpace + "%"
    }

    /// "2 h 15 min", "45 min", "moins d’une minute".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded(.down))
        if minutes < 1 { return "moins d’une minute" }
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    static func day(_ date: Date, calendar: Calendar, locale: Locale = UsageFormat.locale) -> String {
        Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.wide).day().month(.wide).format(date)
    }
}
