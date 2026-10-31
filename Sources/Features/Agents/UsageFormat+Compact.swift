import Foundation

extension UsageFormat {
    /// A cost for a tight column: "$" instead of the long "$US", whole thousands past 10 000 ("12,3 k$"),
    /// never more than about 10 characters, so it is never ellipsized.
    static func costShort(_ value: Double, estimated: Bool, locale: Locale = UsageFormat.locale) -> String {
        let prefix = estimated ? "~" : ""
        if value >= 10_000 {
            let thousands = (value / 1_000).formatted(.number.precision(.fractionLength(1)).locale(locale))
            return prefix + thousands + thinSpace + "k$"
        }
        let full = value.formatted(.currency(code: "USD").precision(.fractionLength(2)).locale(locale))
        return prefix + full.replacingOccurrences(of: "US", with: "")
    }

    /// Tokens with the trailing ",0" dropped ("10 Md" rather than "10,0 Md"): shorter in a tight column.
    static func tokensShort(_ n: Int, locale: Locale = UsageFormat.locale) -> String {
        let text = tokens(n, locale: locale)
        let zero = (0.0).formatted(.number.precision(.fractionLength(1)).locale(locale))   // "0,0"
        let decimal = String(zero.dropFirst().prefix(1))                                     // ","
        return text.replacingOccurrences(of: decimal + "0" + thinSpace, with: thinSpace)
    }
}
