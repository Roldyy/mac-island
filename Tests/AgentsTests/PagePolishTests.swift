import Foundation
import Testing
@testable import AgentsFeature

@Suite struct PagePolishTests {
    @Test func limitLevelFollowsWhatIsLeft() {
        #expect(LimitLevel(leftPercent: 100) == .comfortable)
        #expect(LimitLevel(leftPercent: 51) == .comfortable)
        #expect(LimitLevel(leftPercent: 50) == .watch)
        #expect(LimitLevel(leftPercent: 20) == .watch)
        #expect(LimitLevel(leftPercent: 19) == .critical)
        #expect(LimitLevel(leftPercent: 0) == .critical)
        #expect(LimitRow(kind: .session, usedPercent: 97).level == .critical)
        #expect(LimitRow(kind: .weekly, usedPercent: 58).leftPercent == 42)
        #expect(LimitRow(kind: .weekly, usedPercent: nil).level == nil)
    }

    @Test func aSampleOlderThanTheOpenBlockNeverPassesForTheCurrentSession() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let block = UsageBlock(start: now.addingTimeInterval(-2 * 3600), end: now.addingTimeInterval(3 * 3600),
                               lastActivity: now.addingTimeInterval(-60), tokens: 5_000, cost: 1, estimated: false)
        let old = PlanLimitSample(date: now.addingTimeInterval(-3 * 3600), fiveHour: 3, sevenDay: 58)
        let state = LimitsState.resolve(sample: old, block: block, weekTokens: 9_000, now: now)
        #expect(state.source == .planFile && state.hasEstimatedRow)
        #expect(state.rows.first?.usedPercent == nil && state.rows.first?.tokens == 5_000)
        #expect(state.rows.last?.usedPercent == 58)
        let fresh = PlanLimitSample(date: now.addingTimeInterval(-60), fiveHour: 3, sevenDay: 58)
        let ok = LimitsState.resolve(sample: fresh, block: block, weekTokens: 9_000, now: now)
        #expect(ok.rows.first?.usedPercent == 3 && !ok.hasEstimatedRow)
    }

    @Test func eachLevelHasAWordAndADistinctSymbol() {
        let levels: [LimitLevel] = [.comfortable, .watch, .critical]
        #expect(Set(levels.map(\.label)).count == 3)
        #expect(Set(levels.map(\.status.symbol)).count == 3)
    }

    @Test func modelNamesAreShortened() {
        #expect(ModelFamily.displayName("claude-sonnet-4-5") == "Sonnet 4.5")
        #expect(ModelFamily.displayName("claude-opus-4-1-20250805") == "Opus 4.1")
        #expect(ModelFamily.displayName("claude-3-5-haiku-20241022") == "Haiku 3.5")
        #expect(ModelFamily.displayName("<synthetic>") == "<synthetic>")
    }

    @Test func monthLabelsSitOnTheFirstColumnOfAMonthAndNeverTouch() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        func day(_ m: Int, _ d: Int) -> Date? { DateComponents(calendar: calendar, year: 2026, month: m, day: d).date }
        let columns = [day(8, 3), day(8, 10), day(8, 17), day(8, 24), day(8, 31), day(9, 7), day(9, 14), day(9, 21)]
        let names = AgentsActivityCard.monthNames(columns, calendar: calendar, locale: Locale(identifier: "fr_BE"))
        #expect(names.count == columns.count)
        #expect(names[0] == "août" && names[5] == "sept.")
        #expect(names.filter { !$0.isEmpty }.count == 2)
    }
}
