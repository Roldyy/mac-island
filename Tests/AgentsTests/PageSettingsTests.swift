import ClaudeLiveKit
import Foundation
import Testing
@testable import AgentsFeature

@Suite struct PageSettingsTests {
    // MARK: card order and hidden cards

    @Test func defaultOrderIsTheSpecOne() {
        #expect(AgentsCard.allCases.map(\.rawValue) == ["limits", "spend", "live", "trend", "models", "projects", "activity", "resets"])
        let store = WindowTests.FakeStore()
        #expect(AgentsSettings(store: store).cardOrder == AgentsCard.allCases)
        #expect(AgentsSettings(store: store).hiddenCards.isEmpty)
    }

    @Test func cardOrderAndHiddenCardsRoundTrip() {
        let store = WindowTests.FakeStore()
        let settings = AgentsSettings(store: store)
        let order: [AgentsCard] = [.activity, .limits, .spend, .live, .trend, .models, .projects, .resets]
        settings.save(cardOrder: order)
        settings.save(hiddenCards: [.models, .live])
        #expect(settings.cardOrder == order)
        #expect(settings.hiddenCards == [.models, .live])
        #expect(store.values["notchAgentsCardOrder"] as? [String] == order.map(\.rawValue))
        #expect(store.values["notchAgentsHiddenCards"] as? [String] == ["live", "models"])
    }

    @Test func storedOrderToleratesUnknownRepeatedAndMissingIds() {
        #expect(AgentsCardLayout.order(from: ["trend", "bogus", "trend", "limits"])
            == [.trend, .limits, .spend, .live, .models, .projects, .activity, .resets])
        #expect(AgentsCardLayout.order(from: 42) == AgentsCard.allCases)
        #expect(AgentsCardLayout.order(from: "spend, limits") == [.spend, .limits, .live, .trend, .models, .projects, .activity, .resets])
        #expect(AgentsCardLayout.hidden(from: "models,nope") == [.models])
    }

    @Test func resetsIsHiddenEntirelyWithoutCodexData() {
        let all = AgentsCard.allCases
        #expect(!AgentsCardLayout.visible(order: all, hidden: [], hasCodexData: false).contains(.resets))
        #expect(AgentsCardLayout.visible(order: all, hidden: [], hasCodexData: true).contains(.resets))
        #expect(!AgentsCardLayout.visible(order: all, hidden: [.spend], hasCodexData: true).contains(.spend))
    }

    @Test func halfWidthCardsPairUpAndChartsTakeTheWholeRow() {
        let rows = AgentsCardLayout.rows([.limits, .spend, .live, .trend, .models, .projects, .activity])
        #expect(rows == [[.limits], [.spend, .live], [.trend], [.models, .projects], [.activity]])
        #expect(AgentsCardLayout.rows([.limits, .trend]) == [[.limits], [.trend]])
        #expect(AgentsCardLayout.rows([]).isEmpty)
    }

    @Test func movingACardClampsAtTheEnds() {
        let order = AgentsCard.allCases
        #expect(AgentsCardLayout.moved(.spend, by: -1, in: order).prefix(2) == [.spend, .limits])
        #expect(AgentsCardLayout.moved(.limits, by: -1, in: order) == order)
        #expect(AgentsCardLayout.moved(.resets, by: 1, in: order) == order)
        #expect(AgentsCardLayout.moved(.limits, by: 99, in: order).last == .limits)
    }

    // MARK: other keys

    @Test func limitDisplayFocusAndBudgetDefaultsAndRoundTrip() {
        let store = WindowTests.FakeStore()
        let settings = AgentsSettings(store: store)
        #expect(settings.limitDisplay == .remaining && settings.limitFocus == .mostUsed && settings.dailyBudget == nil)
        settings.save(limitDisplay: .used)
        settings.save(limitFocus: .weekly)
        settings.save(dailyBudget: 25)
        #expect(store.values["notchAgentsLimitDisplay"] as? String == "used")
        #expect(store.values["notchAgentsLimitFocus"] as? String == "weekly")
        #expect(settings.limitDisplay == .used && settings.limitFocus == .weekly && settings.dailyBudget == 25)
        settings.save(dailyBudget: nil)
        #expect(settings.dailyBudget == nil)
        store.values["notchAgentsDailyBudget"] = -4
        #expect(settings.dailyBudget == nil)
        store.values["notchAgentsLimitFocus"] = "nonsense"
        #expect(settings.limitFocus == .mostUsed)
    }

    @Test func closedIslandOnlyWhenIdleContentIsAgents() {
        let store = WindowTests.FakeStore()
        #expect(!AgentsSettings(store: store).showsLimitWhenClosed)
        store.values["notchIdleContent"] = "agents"
        #expect(AgentsSettings(store: store).showsLimitWhenClosed)
        store.values["notchIdleContent"] = "clock"
        #expect(!AgentsSettings(store: store).showsLimitWhenClosed)
    }

    // MARK: period mapping

    @Test func periodsMapToTodayAWeekAndThirtyDays() {
        #expect(UsagePeriod.allCases.map(\.rawValue) == ["today", "week", "month"])
        #expect(UsagePeriod.allCases.map(\.days) == [1, 7, 30])
        #expect(UsagePeriod.allCases.map(\.title) == ["Aujourd’hui", "7 jours", "30 jours"])
        let calendar = WindowTests.calendar
        let month = UsagePeriod.month.interval(now: WindowTests.now, calendar: calendar)
        #expect(month.start == AggregationTests.date("2026-09-22T00:00:00Z"))
        #expect(month.end == AggregationTests.date("2026-10-22T00:00:00Z"))
    }

    // MARK: pure helpers behind the cards

    @Test func trendBucketsFillQuietHoursAndDays() {
        let calendar = WindowTests.calendar
        let records = [WindowTests.rec("a", "2026-10-21T09:10:00Z", o: 50), WindowTests.rec("b", "2026-10-19T09:10:00Z", o: 70)]
        let today = UsageAggregator.summarize(records, now: WindowTests.now, calendar: calendar, period: .today)
        let hours = TrendBuckets.make(summary: today, period: .today, now: WindowTests.now, calendar: calendar)
        #expect(hours.count == 15 && hours[9].tokens == 50 && hours[0].tokens == 0)   // 00 h ... 14 h
        let week = UsageAggregator.summarize(records, now: WindowTests.now, calendar: calendar, period: .week)
        let days = TrendBuckets.make(summary: week, period: .week, now: WindowTests.now, calendar: calendar)
        #expect(days.count == 7 && days.map(\.tokens) == [0, 0, 0, 0, 70, 0, 50])
    }

    @Test func barsAreStackedPerModelFamily() {
        let records = [WindowTests.rec("a", "2026-10-21T09:10:00Z", o: 50, model: "claude-opus-5-5"),
                       WindowTests.rec("b", "2026-10-21T09:20:00Z", o: 30, model: "claude-sonnet-5-5"),
                       WindowTests.rec("c", "2026-10-21T09:30:00Z", o: 5, model: "mystery")]
        let s = UsageAggregator.summarize(records, now: WindowTests.now, calendar: WindowTests.calendar, period: .today)
        #expect(s.perHour.first?.shares.map(\.family) == [.opus, .sonnet, .other])
        #expect(s.perHour.first?.shares.map(\.tokens) == [50, 30, 5])
    }

    @Test func spendFiguresCountOutputCacheAndSavings() {
        let record = AggregationTests.rec("a", "claude-sonnet-5-5", "2026-10-21T10:00:00Z", i: 10, o: 20, cw: 30, cr: 1_000_000)
        let s = UsageAggregator.summarize([record], now: WindowTests.now, calendar: WindowTests.calendar, period: .today)
        #expect(s.outputTokens == 20 && s.cacheReadTokens == 1_000_000 && s.cacheWriteTokens == 30)
        #expect(abs(s.cacheSavings - 2.7) < 1e-9)   // 1 M tokens at (3 - 0.3) USD per million
    }

    @Test func olderModelsGetTheirOwnPriceAndUnknownOnesStayMinimum() {
        #expect(PriceTable.price(for: "claude-opus-4-1-20250805").perMillion.output == 75)
        #expect(PriceTable.price(for: "claude-opus-5-5").perMillion.output == 25)
        #expect(PriceTable.price(for: "claude-3-5-haiku-20241022").perMillion.input == 0.8)
        #expect(PriceTable.price(for: "claude-haiku-4-5").perMillion.input == 1)
        #expect(PriceTable.price(for: "gemini-x").estimated)
    }

    @Test func heatmapStatsCountStreakActiveDaysAndBusiestDay() {
        let calendar = WindowTests.calendar
        let records = [
            WindowTests.rec("t", "2026-10-21T09:00:00Z", o: 10), WindowTests.rec("y", "2026-10-20T09:00:00Z", o: 90),
            WindowTests.rec("b", "2026-10-19T09:00:00Z", o: 10), WindowTests.rec("g", "2026-10-17T09:00:00Z", o: 10),
        ]
        let map = UsageHeatmap.build(records, now: WindowTests.now, calendar: calendar)
        let stats = HeatmapStats.compute(map, now: WindowTests.now, calendar: calendar)
        #expect(stats.streak == 3 && stats.activeDays == 4)
        #expect(stats.busiest?.day == AggregationTests.date("2026-10-20T00:00:00Z"))
        // A quiet today does not break the streak yet.
        let quiet = HeatmapStats.compute(UsageHeatmap.build(Array(records.dropFirst()), now: WindowTests.now, calendar: calendar),
                                         now: WindowTests.now, calendar: calendar)
        #expect(quiet.streak == 2)
        #expect(HeatmapStats.compute(UsageHeatmap.build([], now: WindowTests.now, calendar: calendar),
                                     now: WindowTests.now, calendar: calendar) == HeatmapStats())
    }

    @Test func planTierReadsOnlyTheRateLimitTier() {
        #expect(PlanTier(rateLimitTier: "default_claude_max_5x") == .max5x)
        #expect(PlanTier(rateLimitTier: "default_claude_max_20x") == .max20x)
        #expect(PlanTier(rateLimitTier: "default_claude_pro") == .pro)
        #expect(PlanTier(rateLimitTier: "default_raven") == nil && PlanTier(rateLimitTier: nil) == nil)
        let json = Data(#"{"oauthAccount":{"emailAddress":"a@b.c","userRateLimitTier":"default_claude_max_5x"}}"#.utf8)
        #expect(PlanTierSource.rateLimitTier(from: json) == "default_claude_max_5x")
        #expect(PlanTierSource.rateLimitTier(from: Data("{}".utf8)) == nil)
        #expect(PlanTier.max5x.price(forDays: 30) == 100 && abs(PlanTier.max5x.price(forDays: 7) - 700.0 / 30) < 1e-9)
        #expect(PlanTier.max5x.multiple(apiValue: 350, days: 30) == 3.5)
        #expect(PlanTier.max5x.multiple(apiValue: 0, days: 30) == nil)
    }

    @Test func finishTrackerNoticesASessionThatStoppedWorking() {
        func session(_ id: String, _ state: ClaudeSession.State, _ folder: String = "proj") -> ClaudeSession {
            ClaudeSession(id: id, pid: 1, state: state, folderName: folder)
        }
        var tracker = FinishTracker()
        let t0 = Date(timeIntervalSince1970: 1000)
        tracker.update([session("a", .working)], now: t0)
        #expect(tracker.last == nil)
        tracker.update([session("a", .working), session("b", .idle, "other")], now: t0)
        #expect(tracker.last == nil)
        tracker.update([session("a", .idle)], now: t0.addingTimeInterval(5))
        #expect(tracker.last == FinishedSession(folderName: "proj", at: t0.addingTimeInterval(5)))
        tracker.update([], now: t0.addingTimeInterval(9))   // nothing was working: no new event
        #expect(tracker.last?.at == t0.addingTimeInterval(5))
    }
}
