import Foundation
import Testing
@testable import AgentsFeature

/// Fixed clock: Wednesday 2026-10-21 14:30 UTC, calendar in UTC with Monday first.
@Suite struct WindowTests {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }

    static let now = AggregationTests.date("2026-10-21T14:30:00Z")

    static func rec(_ id: String, _ ts: String, o: Int = 100, model: String = "claude-sonnet-5-5",
                    project: String = "") -> UsageRecord {
        UsageRecord(messageID: id, model: model, timestamp: AggregationTests.date(ts),
                    inputTokens: 0, outputTokens: o, cacheCreationTokens: 0, cacheReadTokens: 0, project: project)
    }

    // MARK: periods

    @Test func todayCoversOnlyTheCurrentDayAndFillsHours() {
        let records = [
            Self.rec("a", "2026-10-21T00:00:00Z"), Self.rec("b", "2026-10-21T09:10:00Z", o: 50),
            Self.rec("c", "2026-10-21T09:50:00Z", o: 50), Self.rec("d", "2026-10-20T23:59:59Z"),
        ]
        let s = UsageAggregator.summarize(records, now: Self.now, calendar: Self.calendar, period: .today)
        #expect(s.totalTokens == 200)
        #expect(s.perHour.map(\.tokens) == [100, 100])
        #expect(UsageAggregator.summarize(records, now: Self.now, calendar: Self.calendar, period: .week).perHour.isEmpty)
    }

    @Test func weekIsRollingSevenDaysEndingToday() {
        let records = [
            Self.rec("in1", "2026-10-15T00:00:00Z"),   // first day of the window (21 - 6)
            Self.rec("in2", "2026-10-21T23:00:00Z"),   // later today still counts
            Self.rec("out", "2026-10-14T23:59:59Z"),
        ]
        let s = UsageAggregator.summarize(records, now: Self.now, calendar: Self.calendar, period: .week)
        #expect(s.totalTokens == 200)
        #expect(s.perDay.count == 2)
    }

    @Test func projectsAreGroupedByFolderNameAndSortedByCost() {
        let records = [
            Self.rec("1", "2026-10-21T10:00:00Z", o: 10, project: "alpha"),
            Self.rec("2", "2026-10-21T10:01:00Z", o: 5_000, project: "beta"),
            Self.rec("3", "2026-10-21T10:02:00Z", o: 10),
        ]
        let s = UsageAggregator.summarize(records, now: Self.now, calendar: Self.calendar, period: .today)
        #expect(s.perProject.first?.name == "beta")
        #expect(Set(s.perProject.map(\.name)) == ["alpha", "beta", UsageAggregator.noProject])
    }

    @Test func periodFromStoredValue() {
        #expect(UsagePeriod(rawValue: "today") == .today)
        #expect(UsagePeriod(rawValue: "week") == .week)
        #expect(UsagePeriod(rawValue: "month") == .month)
        #expect(UsagePeriod(rawValue: "year") == nil)
    }

    // MARK: 5 h block

    @Test func blockStartsFlooredToTheHourAndCountsSinceThen() {
        let records = [Self.rec("a", "2026-10-21T12:20:00Z", o: 10), Self.rec("b", "2026-10-21T14:00:00Z", o: 20)]
        let block = UsageBlocks.active(records, now: Self.now)
        #expect(block?.start == AggregationTests.date("2026-10-21T12:00:00Z"))
        #expect(block?.end == AggregationTests.date("2026-10-21T17:00:00Z"))
        #expect(block?.tokens == 30)
        #expect(block?.remaining(at: Self.now) == 2.5 * 3600)
    }

    @Test func gapOverFiveHoursStartsANewBlock() {
        let records = [Self.rec("old", "2026-10-21T01:00:00Z", o: 999), Self.rec("new", "2026-10-21T13:00:00Z", o: 5)]
        let block = UsageBlocks.active(records, now: Self.now)
        #expect(block?.tokens == 5)
        #expect(block?.start == AggregationTests.date("2026-10-21T13:00:00Z"))
    }

    @Test func messageAfterBlockEndStartsANewBlockEvenWithoutGap() {
        // Messages every 2 h: the block opened at 08:00 ends at 13:00, so the 14:00 message opens a new one.
        let records = [Self.rec("a", "2026-10-21T08:30:00Z", o: 1), Self.rec("b", "2026-10-21T10:30:00Z", o: 2),
                       Self.rec("c", "2026-10-21T12:30:00Z", o: 3), Self.rec("d", "2026-10-21T14:10:00Z", o: 4)]
        let block = UsageBlocks.active(records, now: Self.now)
        #expect(block?.start == AggregationTests.date("2026-10-21T14:00:00Z"))
        #expect(block?.tokens == 4)
    }

    @Test func noActiveBlockWhenTheLastOneIsOver() {
        let records = [Self.rec("a", "2026-10-21T02:00:00Z")]
        #expect(UsageBlocks.active(records, now: Self.now) == nil)
        #expect(UsageBlocks.active([], now: Self.now) == nil)
    }

    @Test func blockIgnoresRecordsInTheFutureAndMarksUnknownPricesEstimated() {
        let records = [Self.rec("a", "2026-10-21T14:00:00Z", model: "mystery"), Self.rec("f", "2026-10-21T20:00:00Z")]
        let block = UsageBlocks.active(records, now: Self.now)
        #expect(block?.tokens == 100)
        #expect(block?.estimated == true)
    }

    // MARK: heatmap

    @Test func heatmapIsThirteenWeeksBySevenDaysEndingInTheCurrentWeek() {
        let map = UsageHeatmap.build([], now: Self.now, calendar: Self.calendar)
        #expect(map.columns.count == 13)
        #expect(map.columns.allSatisfy { $0.count == 7 })
        // Monday first: the last column starts Monday 2026-10-19, today is its third row.
        #expect(map.columns[12][0].day == AggregationTests.date("2026-10-19T00:00:00Z"))
        #expect(map.columns[12][2].day == AggregationTests.date("2026-10-21T00:00:00Z"))
        #expect(map.columns[12][3].isFuture)
        #expect(!map.columns[12][2].isFuture)
        #expect(map.columns[0][0].day == AggregationTests.date("2026-07-27T00:00:00Z"))
    }

    @Test func heatmapBucketsTokensPerDayWithLevelsRelativeToPeak() {
        let records = [
            Self.rec("a", "2026-10-21T01:00:00Z", o: 1000),     // peak, today
            Self.rec("b", "2026-10-21T09:00:00Z", o: 1000),     // same day: 2000
            Self.rec("c", "2026-10-20T09:00:00Z", o: 1000),     // half of peak
            Self.rec("d", "2026-10-19T09:00:00Z", o: 10),       // tiny but nonzero: level 1
            Self.rec("old", "2026-07-01T09:00:00Z", o: 99_999), // outside the grid
            Self.rec("future", "2026-10-22T09:00:00Z", o: 5),   // not happened yet
        ]
        let map = UsageHeatmap.build(records, now: Self.now, calendar: Self.calendar)
        #expect(map.peak == 2000)
        #expect(map.columns[12][2].tokens == 2000 && map.columns[12][2].level == 4)
        #expect(map.columns[12][1].tokens == 1000 && map.columns[12][1].level == 2)
        #expect(map.columns[12][0].level == 1)
        #expect(map.columns[12][3].level == 0 && map.columns[12][3].tokens == 0)
    }

    @Test func snapshotCombinesWindowsAndWeekTotal() {
        let records = [Self.rec("a", "2026-10-21T13:00:00Z", o: 10), Self.rec("b", "2026-10-16T13:00:00Z", o: 20),
                       Self.rec("c", "2026-10-02T13:00:00Z", o: 40)]
        let snap = UsageSnapshot.build(records, now: Self.now, calendar: Self.calendar)
        #expect(snap.summary(for: .today).totalTokens == 10)
        #expect(snap.summary(for: .week).totalTokens == 30)
        #expect(snap.summary(for: .month).totalTokens == 70)
        #expect(snap.week.tokens == 30)
        #expect(snap.block?.tokens == 10)
        #expect(UsageSnapshot.windowStart(now: Self.now, calendar: Self.calendar)
            == AggregationTests.date("2026-07-27T00:00:00Z"))
    }

    // MARK: settings and status

    final class FakeStore: AgentsKeyValueStore {
        var values: [String: Any] = [:]
        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
    }

    @Test func periodDefaultsToMonthReadsAndPersistsTheMigratedKey() {
        let store = FakeStore()
        let settings = AgentsSettings(store: store)
        #expect(settings.period == .month)
        store.values["notchAgentsPeriod"] = "week"
        #expect(settings.period == .week)
        settings.save(period: .today)
        #expect(store.values["notchAgentsPeriod"] as? String == "today")
        store.values["notchAgentsPeriod"] = 42
        #expect(settings.period == .month)
    }

    @Test func statusWording() {
        var missing = UsageLoadResult(); missing.directoryMissing = true
        var unreadable = UsageLoadResult(); unreadable.unreadableFiles = 2
        var readable = UsageLoadResult(); readable.fileCount = 3
        #expect(AgentsDataStatus.resolve(hasLoaded: false, sources: [], recordCount: 0) == .loading)
        #expect(AgentsDataStatus.resolve(hasLoaded: true, sources: [missing, missing], recordCount: 0) == .noSource)
        #expect(AgentsDataStatus.resolve(hasLoaded: true, sources: [unreadable, missing], recordCount: 0) == .unreadable)
        #expect(AgentsDataStatus.resolve(hasLoaded: true, sources: [readable, missing], recordCount: 0) == .empty)
        #expect(AgentsDataStatus.resolve(hasLoaded: true, sources: [readable], recordCount: 4) == .ready)
    }

    // MARK: formatting

    @Test func frenchFormatting() {
        let fr = Locale(identifier: "fr_BE")
        #expect(UsageFormat.tokens(950, locale: fr) == "950")
        #expect(UsageFormat.tokens(1_500, locale: fr) == "1,5\u{202F}k")
        #expect(UsageFormat.tokens(2_340_000, locale: fr) == "2,3\u{202F}M")
        #expect(UsageFormat.percent(0.42, locale: fr) == "42\u{202F}%")
        #expect(UsageFormat.cost(1.5, estimated: true, locale: fr).hasPrefix("~"))
        #expect(UsageFormat.duration(2 * 3600 + 15 * 60) == "2 h 15 min")
        #expect(UsageFormat.duration(45 * 60) == "45 min")
        #expect(UsageFormat.duration(10) == "moins d’une minute")
    }
}
