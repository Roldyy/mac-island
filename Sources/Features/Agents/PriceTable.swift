import Foundation

/// USD per million tokens.
struct ModelPrice: Equatable, Sendable {
    var input: Double
    var output: Double
    var cacheWrite: Double
    var cacheRead: Double

    func cost(of record: UsageRecord) -> Double {
        (Double(record.inputTokens) * input
            + Double(record.outputTokens) * output
            + Double(record.cacheCreationTokens) * cacheWrite
            + Double(record.cacheReadTokens) * cacheRead) / 1_000_000
    }
}

struct ResolvedPrice: Equatable, Sendable {
    var perMillion: ModelPrice
    /// True when the model matched no family: the cost is a guess.
    var estimated: Bool
}

/// No network lookup. Every figure is UNVERIFIED against Anthropic's price list.
enum PriceTable {
    static let opus = ModelPrice(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.5)       // verify
    static let sonnet = ModelPrice(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.3)     // verify
    static let haiku = ModelPrice(input: 1, output: 5, cacheWrite: 1.25, cacheRead: 0.1)       // verify
    static let unknownModel = ModelPrice(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.3) // verify (sonnet-class guess)
    static let free = ModelPrice(input: 0, output: 0, cacheWrite: 0, cacheRead: 0)

    // Older generations were priced differently; matched by id fragment before the family rule. Verify too.
    static let opusLegacy = ModelPrice(input: 15, output: 75, cacheWrite: 18.75, cacheRead: 1.5)
    static let haiku35 = ModelPrice(input: 0.8, output: 4, cacheWrite: 1, cacheRead: 0.08)
    static let haiku3 = ModelPrice(input: 0.25, output: 1.25, cacheWrite: 0.3, cacheRead: 0.03)

    private final class Memo: @unchecked Sendable {
        let lock = NSLock()
        var prices: [String: ResolvedPrice] = [:]
    }
    private static let memo = Memo()

    /// Resolved once per model id: the snapshot asks for every record, and a handful of ids repeat tens of thousands of times.
    static func price(for model: String) -> ResolvedPrice {
        if let hit = memo.lock.withLock({ memo.prices[model] }) { return hit }
        let resolved = resolve(model)
        memo.lock.withLock { if memo.prices.count < 512 { memo.prices[model] = resolved } }   // bounded: ids come from log files
        return resolved
    }

    private static func resolve(_ model: String) -> ResolvedPrice {
        let name = model.lowercased()
        if name.hasPrefix("<") { return ResolvedPrice(perMillion: free, estimated: false) } // "<synthetic>"
        if ["opus-4-0", "opus-4-1", "opus-4-2025", "3-opus"].contains(where: name.contains) {
            return ResolvedPrice(perMillion: opusLegacy, estimated: false)
        }
        if name.contains("3-5-haiku") { return ResolvedPrice(perMillion: haiku35, estimated: false) }
        if name.contains("3-haiku") { return ResolvedPrice(perMillion: haiku3, estimated: false) }
        if name.contains("opus") { return ResolvedPrice(perMillion: opus, estimated: false) }
        if name.contains("sonnet") { return ResolvedPrice(perMillion: sonnet, estimated: false) }
        if name.contains("haiku") { return ResolvedPrice(perMillion: haiku, estimated: false) }
        return ResolvedPrice(perMillion: unknownModel, estimated: true)
    }
}
