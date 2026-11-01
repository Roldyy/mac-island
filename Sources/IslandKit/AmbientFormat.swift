import Foundation

/// Pure text of the closed island's new indicators: short strings (the pill has no room for more), French
/// decimal comma, and rounding coarse enough that a value only changes when it is worth redrawing.
public enum AmbientFormat {
    // MARK: Numbers

    /// `value` with `digits` decimals and a decimal comma.
    static func decimal(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", value).replacingOccurrences(of: ".", with: ",")
    }

    /// `value` rounded to 3 significant digits ("1,23", "12,3", "123"), never in scientific notation.
    static func threeSignificant(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0" }
        let rounded = (value >= 100 ? value : value >= 10 ? (value * 10).rounded() / 10 : (value * 100).rounded() / 100)
        if rounded >= 100 { return String(Int(rounded.rounded())) }
        // 99.95 rounds to 100.0 at one decimal: print it without a pointless ",0".
        var text = decimal(rounded, digits: rounded >= 10 ? 1 : 2)
        // "1,20" reads "1,2" and "12,0" reads "12": a trailing zero is noise in a pill.
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(",") { text.removeLast() }
        return text
    }

    // MARK: Throughput

    /// "0 Ko/s", "80 Ko/s", "1,23 Mo/s", "12,3 Mo/s", "123 Mo/s". 1000-based, as the network counts.
    /// Under 1 Ko/s is background noise and reads as zero.
    public static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond >= 1000 else { return "0 Ko/s" }
        var value = bytesPerSecond / 1000
        for unit in ["Ko/s", "Mo/s", "Go/s"] {
            // 999.6 Ko/s would print as "1000": it is "1 Mo/s".
            if value < 999.5 || unit == "Go/s" { return "\(threeSignificant(value)) \(unit)" }
            value /= 1000
        }
        return "0 Ko/s"
    }

    // MARK: Percent

    /// A percentage rounded to the nearest multiple of `step`, clamped to 0...100. CPU uses 5, so a load that
    /// wobbles between 31 and 34 % never redraws the pill.
    public static func roundedPercent(_ fraction: Double, step: Int = 5) -> Int {
        guard fraction.isFinite else { return 0 }
        let percent = min(max(fraction, 0), 1) * 100
        let step = Double(max(step, 1))
        return min(100, Int((percent / step).rounded() * step))
    }

    public static func percent(_ fraction: Double, step: Int = 5) -> String { "\(roundedPercent(fraction, step: step))%" }

    // MARK: Sizes

    /// "9,2 Go", "128 Go", "1,2 To": memory in use or space free. Decimal units, like Finder.
    public static func gigabytes(_ bytes: UInt64) -> String {
        let go = Double(bytes) / 1e9
        if go >= 1000 {
            let to = go / 1000
            return "\(to >= 10 ? String(Int(to.rounded())) : decimal(to, digits: 1)) To"
        }
        if go >= 100 { return "\(Int(go.rounded())) Go" }
        if go >= 10 { return "\(Int(go.rounded())) Go" }
        return "\(decimal(go, digits: 1)) Go"
    }

    // MARK: Time

    /// "14:32" or "2:32 PM": the hour cycle of `locale` unless `hours` forces one.
    public static func time(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current, hours: ClockHours = .system) -> String {
        let template: String
        switch hours {
        case .system: template = "jmm"
        case .h24: template = "HHmm"
        case .h12: template = "hmma"
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: locale)
        return formatter.string(from: date)
    }

    /// "sam. 1 nov": weekday, day and month, abbreviated, without the trailing period CLDR adds to the month.
    public static func shortDate(_ date: Date, locale: Locale = Locale(identifier: "fr_FR"), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "EEEdMMM", options: 0, locale: locale)
        var text = formatter.string(from: date)
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// Seconds to the next full minute, so the clock redraws exactly when its text changes (and never between).
    public static func secondsToNextMinute(from date: Date) -> TimeInterval {
        let into = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
        let left = 60 - (into < 0 ? into + 60 : into)
        return left > 0 ? left : 60
    }
}
