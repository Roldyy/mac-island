import Foundation

/// "il y a 2 h" for the idle card, in French, without a formatter that depends on the Mac's language.
public enum LastTrackRelativeTime {
    public static func text(since date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "à l’instant" }
        if seconds < 3_600 { return "il y a \(Int(seconds / 60)) min" }
        if seconds < 86_400 { return "il y a \(Int(seconds / 3_600)) h" }
        if seconds < 2 * 86_400 { return "hier" }
        if seconds < 7 * 86_400 { return "il y a \(Int(seconds / 86_400)) j" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return "le " + formatter.string(from: date)
    }
}
