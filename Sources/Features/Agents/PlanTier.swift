import Foundation

/// The subscription plan, for the "x times the price of ..." line. Only the rate-limit tier string of
/// `~/.claude.json` (`oauthAccount.userRateLimitTier`) is read: no name, e-mail or id ever leaves the file.
/// Prices are USD per month and UNVERIFIED against Anthropic's list.
struct PlanTier: Equatable, Sendable {
    var name: String
    var monthlyPrice: Double

    static let pro = PlanTier(name: "Pro", monthlyPrice: 20)
    static let max5x = PlanTier(name: "Max 5x", monthlyPrice: 100)
    static let max20x = PlanTier(name: "Max 20x", monthlyPrice: 200)

    /// nil for a tier we do not know (team, enterprise, free...): the comparison line is then left out.
    init?(rateLimitTier: String?) {
        let tier = (rateLimitTier ?? "").lowercased()
        if tier.contains("max_20x") { self = .max20x }
        else if tier.contains("max_5x") { self = .max5x }
        else if tier.hasSuffix("claude_pro") { self = .pro }
        else { return nil }
    }

    private init(name: String, monthlyPrice: Double) {
        self.name = name
        self.monthlyPrice = monthlyPrice
    }

    /// Price of the plan for a window of `days` days (the monthly price spread over 30 days).
    func price(forDays days: Int) -> Double { monthlyPrice * Double(days) / 30 }

    /// API value divided by the plan price of the period; nil when either side is zero.
    func multiple(apiValue: Double, days: Int) -> Double? {
        let price = price(forDays: days)
        guard apiValue > 0, price > 0 else { return nil }
        return apiValue / price
    }
}

enum PlanTierSource {
    /// Extracts the tier string from the JSON of `~/.claude.json`; everything else is dropped at once.
    static func rateLimitTier(from data: Data) -> String? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let account = root["oauthAccount"] as? [String: Any] else { return nil }
        return account["userRateLimitTier"] as? String
    }

    static let maxBytes = 20_000_000

    static func load(url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")) -> PlanTier? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size > 0, size <= maxBytes, let data = try? Data(contentsOf: url) else { return nil }
        return PlanTier(rateLimitTier: rateLimitTier(from: data))
    }
}
