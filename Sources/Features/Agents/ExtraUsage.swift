import Foundation

/// The extra-usage credit (a monthly spending limit beyond the plan), as Claude Code last cached it in
/// `~/.claude.json` (`cachedUsageUtilization.utilization.extra_usage`). Read from that file only: no network,
/// no Keychain. The cache is as old as the last time Claude Code asked, so the age is part of the value and the
/// page greys the numbers out once they are stale.
///
/// INFERRED, not documented: amounts are minor units (`decimal_places` 2 -> cents). To check once against `/usage`.
struct ExtraUsage: Equatable, Sendable {
    var isEnabled: Bool
    /// Major units (euros), already divided by `decimal_places`.
    var limit: Double?
    var used: Double?
    /// 0...100.
    var percent: Double?
    var currency: String
    var limitReached: Bool
    var disabledReason: String?
    var fetchedAt: Date?

    /// A reading older than this is dimmed and says so: "limit not reached" from three days ago is the one
    /// number on the page that can mislead.
    static let staleAfter: TimeInterval = 24 * 3600

    func isStale(at now: Date) -> Bool {
        guard let fetchedAt else { return true }
        return now.timeIntervalSince(fetchedAt) > Self.staleAfter
    }

    func ageText(at now: Date) -> String {
        guard let fetchedAt else { return "date inconnue" }
        let seconds = max(0, now.timeIntervalSince(fetchedAt))
        if seconds < 60 { return "à l’instant" }
        if seconds < 3600 { return "il y a \(Int(seconds / 60)) min" }
        if seconds < 86_400 { return "il y a \(Int(seconds / 3600)) h" }
        return "il y a \(Int(seconds / 86_400)) j"
    }

    /// What the gauge says besides the amounts. nil while the credit is on and not used up.
    var statusText: String? {
        if limitReached { return "Plafond atteint" }
        if let reason = disabledReason {
            return reason == "org_spend_cap_reached" ? "Plafond de l’organisation atteint" : "Désactivé : \(reason)"
        }
        return isEnabled ? nil : "Désactivé"
    }

    /// 0...1 for the bar.
    var fill: Double {
        if limitReached { return 1 }
        return min(max((percent ?? 0) / 100, 0), 1)
    }
}

enum ExtraUsageParser {
    static func parse(_ data: Data) -> ExtraUsage? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let cache = root["cachedUsageUtilization"] as? [String: Any],
              let utilization = cache["utilization"] as? [String: Any],
              let extra = utilization["extra_usage"] as? [String: Any] else { return nil }
        // Clamped as a Double first: Int(Double) traps outside the Int range, and this runs at every launch.
        let places = number(extra["decimal_places"]).map { Int(min(max($0, 0), 6)) } ?? 2
        let divisor = pow(10.0, Double(places))
        let limit = number(extra["monthly_limit"]).map { $0 / divisor }
        let used = number(extra["used_credits"]).map { $0 / divisor }
        var percent = number(extra["utilization"])
        if percent == nil, let limit, limit > 0, let used { percent = used / limit * 100 }
        let enabled = (extra["is_enabled"] as? Bool) ?? false
        // The cache keeps a second, root-level reason that outlives the state it described: it only counts while the
        // feature is off.
        let reason = (extra["disabled_reason"] as? String)
            ?? (enabled ? nil : root["cachedExtraUsageDisabledReason"] as? String)
        return ExtraUsage(
            isEnabled: enabled, limit: limit, used: used, percent: percent,
            currency: (extra["currency"] as? String) ?? "EUR",
            limitReached: (extra["spend_limit_reached"] as? Bool) ?? false,
            disabledReason: reason,
            fetchedAt: number(cache["fetchedAtMs"]).map { Date(timeIntervalSince1970: $0 / 1000) })
    }

    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }
}

/// Reads the file. The path is injected; the default is Claude Code's own `~/.claude.json`.
struct ExtraUsageSource: Sendable {
    var url: URL
    /// The file also holds the project history and can reach a few MB; refuse anything absurd.
    var maxBytes = 30_000_000

    init(url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json"),
         maxBytes: Int = 30_000_000) {
        self.url = url
        self.maxBytes = maxBytes
    }

    func load() -> ExtraUsage? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size > 0, size <= maxBytes, let data = try? Data(contentsOf: url) else { return nil }
        return ExtraUsageParser.parse(data)
    }
}
