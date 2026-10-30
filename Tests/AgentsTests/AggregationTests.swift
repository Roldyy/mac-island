import Foundation
import Testing
@testable import AgentsFeature

@Suite struct AggregationTests {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    static func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    static func rec(_ id: String, _ model: String, _ ts: String, i: Int = 0, o: Int = 0, cw: Int = 0, cr: Int = 0) -> UsageRecord {
        UsageRecord(messageID: id, model: model, timestamp: date(ts),
                    inputTokens: i, outputTokens: o, cacheCreationTokens: cw, cacheReadTokens: cr)
    }

    @Test func priceTableMatchesFamilyAndFlagsUnknown() {
        let opus = PriceTable.price(for: "claude-opus-5-5")
        let sonnet = PriceTable.price(for: "claude-sonnet-5-5")
        let haiku = PriceTable.price(for: "claude-haiku-4-5-20251001")
        let unknown = PriceTable.price(for: "gpt-weird")
        #expect(!opus.estimated && !sonnet.estimated && !haiku.estimated)
        #expect(opus.perMillion.output > sonnet.perMillion.output)
        #expect(sonnet.perMillion.output > haiku.perMillion.output)
        #expect(unknown.estimated)
    }

    @Test func costIsPerMillionTokens() {
        let p = ModelPrice(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.3)
        let r = Self.rec("a", "m", "2026-10-05T10:00:00Z", i: 1_000_000, o: 1_000_000, cw: 1_000_000, cr: 1_000_000)
        #expect(abs(p.cost(of: r) - 22.05) < 1e-9)
    }

    @Test func aggregatesCurrentMonthOnly() {
        let now = Self.date("2026-10-20T12:00:00Z")
        let records = [
            Self.rec("1", "claude-sonnet-5-5", "2026-10-01T00:00:00Z", i: 100, o: 100),
            Self.rec("2", "claude-sonnet-5-5", "2026-10-05T23:59:59Z", o: 50),
            Self.rec("3", "claude-opus-5-5", "2026-10-05T01:00:00Z", o: 10),
            Self.rec("4", "claude-sonnet-5-5", "2026-09-30T23:59:59Z", o: 999),
            Self.rec("5", "claude-sonnet-5-5", "2026-11-01T00:00:00Z", o: 999),
        ]
        let s = UsageAggregator.summarize(records, now: now, calendar: Self.calendar)
        #expect(s.totalTokens == 260)
        #expect(s.perDay.count == 2)
        #expect(s.perDay.first?.tokens == 200)
        #expect(s.perModel.count == 2)
        #expect(s.perModel.first?.model == "claude-sonnet-5-5")
        #expect(s.perModel.first?.tokens == 250)
        #expect(s.totalCost > 0)
        #expect(!s.costIsEstimated)
    }

    @Test func unknownModelMarksCostEstimated() {
        let now = Self.date("2026-10-20T12:00:00Z")
        let s = UsageAggregator.summarize([Self.rec("1", "mystery-model", "2026-10-02T00:00:00Z", o: 1000)],
                                          now: now, calendar: Self.calendar)
        #expect(s.costIsEstimated)
        #expect(s.totalCost > 0)
    }

    @Test func emptyInputGivesZeroSummary() {
        let s = UsageAggregator.summarize([], now: Date(), calendar: Self.calendar)
        #expect(s.totalTokens == 0 && s.totalCost == 0 && s.perDay.isEmpty && s.perModel.isEmpty)
    }

    @Test func monthStartIsFirstOfMonth() {
        let start = UsageAggregator.monthStart(containing: Self.date("2026-10-20T12:00:00Z"), calendar: Self.calendar)
        #expect(start == Self.date("2026-10-01T00:00:00Z"))
    }
}
