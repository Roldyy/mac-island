import Foundation
import SwiftUI
import Testing
@testable import AgentsFeature

/// A plan-file reading older than the 5 h window can never describe the current session, so it must never be
/// drawn as a live percentage, whatever the loading order (plan limits first, then cache, then the walk).
@Suite struct StaleSessionTests {
    static let now = PlanLimitTests.now   // 2026-10-21 14:30 UTC
    static let hour: TimeInterval = 3600

    static func sample(age: TimeInterval) -> PlanLimitSample {
        PlanLimitSample(date: now.addingTimeInterval(-age), fiveHour: 97, sevenDay: 58)
    }

    static func session(_ state: LimitsState) -> LimitRow? { state.rows.first { $0.kind == .session } }

    // MARK: pure resolution: ages x block known / unknown

    @Test func aFreshReadingIsTheSessionWhateverTheBlockKnowledge() {
        for (known, block) in [(true, PlanLimitTests.block as UsageBlock?), (true, nil), (false, nil)] {
            let state = LimitsState.resolve(sample: Self.sample(age: 60), block: block, blockKnown: known, weekTokens: 0, now: Self.now)
            #expect(Self.session(state)?.usedPercent == 97 && Self.session(state)?.isPending == false)
        }
    }

    @Test func aFourHourReadingStillCountsUnlessTheOpenBlockBeganAfterIt() {
        let sample = Self.sample(age: 4 * Self.hour)   // 10:30, the block opened at 12:00
        let withBlock = Self.session(LimitsState.resolve(sample: sample, block: PlanLimitTests.block, blockKnown: true,
                                                         weekTokens: 0, now: Self.now))
        #expect(withBlock?.usedPercent == nil && withBlock?.tokens == 900 && withBlock?.isPending == false)
        for known in [true, false] {
            let row = Self.session(LimitsState.resolve(sample: sample, block: nil, blockKnown: known, weekTokens: 0, now: Self.now))
            #expect(row?.usedPercent == 97, "known \(known)")
        }
    }

    @Test func aReadingOlderThanFiveHoursIsNeverAPercentage() {
        for age in [5 * Self.hour + 60, 6 * Self.hour, 20 * Self.hour] {
            let sample = Self.sample(age: age)
            // Block known and open: the log estimate.
            let open = LimitsState.resolve(sample: sample, block: PlanLimitTests.block, blockKnown: true, weekTokens: 0, now: Self.now)
            #expect(Self.session(open)?.usedPercent == nil && Self.session(open)?.tokens == 900 && open.hasEstimatedRow)
            // Block known and none open: idle, no number.
            let idle = Self.session(LimitsState.resolve(sample: sample, block: nil, blockKnown: true, weekTokens: 0, now: Self.now))
            #expect(idle?.isIdle == true && idle?.usedPercent == nil)
            // Block not known yet: pending, no number, no tokens.
            for block in [nil, PlanLimitTests.block as UsageBlock?] {
                let pending = Self.session(LimitsState.resolve(sample: sample, block: block, blockKnown: false, weekTokens: 0, now: Self.now))
                #expect(pending?.isPending == true && pending?.usedPercent == nil && pending?.tokens == nil, "age \(age)")
            }
        }
    }

    @Test func theWeekKeepsItsSlowMovingReadingInEveryCase() {
        for known in [true, false] {
            let state = LimitsState.resolve(sample: Self.sample(age: 20 * Self.hour), block: nil, blockKnown: known, weekTokens: 0, now: Self.now)
            let week = state.rows.first { $0.kind == .weekly }
            #expect(week?.usedPercent == 58 && week?.isPending == false)
            #expect(state.source == .planFile && state.updated == Self.now.addingTimeInterval(-20 * Self.hour))
        }
    }

    @Test func withoutASampleTheStatesAreEstimateEmptyOrPending() {
        let known = LimitsState.resolve(sample: nil, block: PlanLimitTests.block, blockKnown: true, weekTokens: 7, now: Self.now)
        #expect(known.source == .estimatedFromLogs && known.rows.allSatisfy { !$0.isPending && $0.usedPercent == nil })
        let partialWeek = LimitsState.resolve(sample: nil, block: PlanLimitTests.block, blockKnown: true, weekTokens: 7,
                                              weekComplete: false, now: Self.now)
        #expect(partialWeek.rows[0].isPending == false && partialWeek.rows[1].isPending && partialWeek.rows[1].tokens == nil)
        #expect(LimitsState.resolve(sample: nil, block: nil, blockKnown: true, weekTokens: 0, now: Self.now).rows.isEmpty)
        let unknown = LimitsState.resolve(sample: nil, block: nil, blockKnown: false, weekTokens: 0, now: Self.now)
        #expect(unknown.source == .none && unknown.rows.count == 2 && unknown.rows.allSatisfy(\.isPending))
    }

    @Test func aPendingRowIsNeverFocusedOnTheClosedIsland() {
        let state = LimitsState.resolve(sample: Self.sample(age: 20 * Self.hour), block: nil, blockKnown: false, weekTokens: 0, now: Self.now)
        #expect(state.focused(.session) == nil)
        #expect(state.focused(.mostUsed)?.kind == .weekly)
    }

    // MARK: the sequence a refresh publishes

    struct ScriptedSource: UsageSource {
        var cached: [UsageRecord] = []
        /// (records known, newest file still to read) per progress report after the folder walk.
        var steps: [(records: [UsageRecord], pendingNewest: Date?, missingNewest: Date?)] = []
        var final: [UsageRecord]

        func load(modifiedSince: Date?) -> UsageLoadResult { UsageLoadResult(records: final) }

        func load(modifiedSince: Date?, shouldContinue: () -> Bool, progress: (UsageProgress) -> Void) -> UsageLoadResult {
            if !cached.isEmpty {
                progress(UsageProgress(result: UsageLoadResult(records: cached), missingNewest: nil, pendingNewest: nil, fromCache: true))
            }
            for step in steps {
                progress(UsageProgress(result: UsageLoadResult(records: step.records), missingNewest: step.missingNewest,
                                       pendingNewest: step.pendingNewest))
            }
            return UsageLoadResult(records: final)
        }
    }

    static func record(minutesAgo: Double) -> UsageRecord {
        UsageRecord(messageID: nil, model: "claude-opus-4-5", timestamp: now.addingTimeInterval(-minutesAgo * 60),
                    inputTokens: 900, outputTokens: 4_000, cacheCreationTokens: 12_000, cacheReadTokens: 180_000, project: "demo")
    }

    static func planFile(age: TimeInterval) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stale-\(UUID().uuidString).json")
        let t = Int(now.addingTimeInterval(-age).timeIntervalSince1970 * 1000)
        try PlanLimitTests.file(PlanLimitTests.sample(t: t, fh: 97, sd: 58)).write(to: url)
        return url
    }

    static func updates(source: ScriptedSource, sampleAge: TimeInterval) throws -> [UsageUpdate] {
        let url = try planFile(age: sampleAge)
        defer { try? FileManager.default.removeItem(at: url) }
        var seen: [UsageUpdate] = []
        UsagePipeline.run(sources: [source], limitSource: PlanLimitSource(url: url), planLoader: { nil }, now: now,
                          calendar: AggregationTests.calendar, shouldContinue: { true }, emit: { seen.append($0) })
        return seen
    }

    @Test func warmStartPublishesTheOpenBlockBeforeAnySnapshotAndNeverAStalePercentage() throws {
        let recent = [Self.record(minutesAgo: 95), Self.record(minutesAgo: 15)]
        let source = ScriptedSource(
            cached: recent,
            steps: [(recent + [Self.record(minutesAgo: 5)], Self.now.addingTimeInterval(-2 * Self.hour), nil)],
            final: recent + [Self.record(minutesAgo: 5)])
        let updates = try Self.updates(source: source, sampleAge: 20 * Self.hour)
        // plan limits only, cache limits only, cache snapshot, one partial, final
        #expect(updates.count == 5)
        #expect(updates.map { $0.snapshot == nil } == [true, true, false, false, false])
        for (index, update) in updates.enumerated() {
            #expect(Self.session(update.limits)?.usedPercent == nil, "update \(index)")
        }
        #expect(Self.session(updates[0].limits)?.isPending == true)
        // From the second update on, the block is known: an estimate with tokens, no placeholder left.
        for update in updates.dropFirst() {
            let row = Self.session(update.limits)
            #expect(row?.isPending == false && (row?.tokens ?? 0) > 0)
        }
        // The week reading is on screen from the very first update.
        #expect(updates[0].limits.rows.first { $0.kind == .weekly }?.usedPercent == 58)
    }

    @Test func coldStartKeepsTheSessionPendingUntilTheNewestFilesAreRead() throws {
        let stepOne = [Self.record(minutesAgo: 400)]
        let stepTwo = stepOne + [Self.record(minutesAgo: 95), Self.record(minutesAgo: 15)]
        let source = ScriptedSource(
            steps: [
                (stepOne, Self.now.addingTimeInterval(-30 * 60), Self.now.addingTimeInterval(-30 * 60)),   // a file of the last 5 h is unread
                (stepTwo, Self.now.addingTimeInterval(-8 * Self.hour), Self.now.addingTimeInterval(-8 * Self.hour)),   // only old ones left
            ],
            final: stepTwo)
        let updates = try Self.updates(source: source, sampleAge: 20 * Self.hour)
        #expect(updates.count == 4)
        for update in updates { #expect(Self.session(update.limits)?.usedPercent == nil) }
        #expect(Self.session(updates[0].limits)?.isPending == true)
        #expect(Self.session(updates[1].limits)?.isPending == true)    // newest file not read yet
        #expect(Self.session(updates[2].limits)?.isPending == false)   // settled
        #expect(Self.session(updates[2].limits)?.tokens != nil)
        #expect(Self.session(updates[3].limits)?.isPending == false)
    }

    @Test func aCacheWithNoOpenBlockDoesNotSettleItUntilTheLastFiveHoursAreRead() throws {
        let old = [Self.record(minutesAgo: 400)]
        let source = ScriptedSource(
            cached: old,
            steps: [(old, Self.now.addingTimeInterval(-10 * 60), nil),
                    (old + [Self.record(minutesAgo: 5)], Self.now.addingTimeInterval(-9 * Self.hour), nil)],
            final: old + [Self.record(minutesAgo: 5)])
        let updates = try Self.updates(source: source, sampleAge: 20 * Self.hour)
        // plan only, cache limits, cache snapshot, partial (file of the last 5 h pending), partial (settled), final
        #expect(updates.count == 6)
        for update in updates { #expect(Self.session(update.limits)?.usedPercent == nil) }
        #expect(updates[1...3].allSatisfy { Self.session($0.limits)?.isPending == true })
        #expect(Self.session(updates[4].limits)?.isPending == false && Self.session(updates[5].limits)?.tokens != nil)
    }

    @Test func aFourHourReadingWithNoBlockInTheCacheMayShowAsThePlanSaysUntilTheLogsDisagree() throws {
        let source = ScriptedSource(steps: [], final: [Self.record(minutesAgo: 15)])
        let updates = try Self.updates(source: source, sampleAge: 4 * Self.hour)
        #expect(Self.session(updates[0].limits)?.usedPercent == 97)
        // The last update: a block opened at 14:00, after the 10:30 reading, so the estimate replaces it.
        #expect(Self.session(updates.last!.limits)?.usedPercent == nil)
        #expect(Self.session(updates.last!.limits)?.tokens != nil)
    }

    @Test func everyPartialSnapshotKeepsItsTotalsMarkedUntilCovered() throws {
        // Cold start: today's file is the newest and not read yet, so today must not claim to be complete.
        let startOfToday = AggregationTests.calendar.startOfDay(for: Self.now)
        let source = ScriptedSource(
            steps: [([Self.record(minutesAgo: 3000)], Self.now.addingTimeInterval(-60), Self.now.addingTimeInterval(-60))],
            final: [Self.record(minutesAgo: 3000), Self.record(minutesAgo: 15)])
        let updates = try Self.updates(source: source, sampleAge: 20 * Self.hour)
        let partial = try #require(updates.dropFirst().first)
        #expect(!partial.coverage.covers(.today, now: Self.now, calendar: AggregationTests.calendar))
        #expect(!partial.coverage.covers(.week, now: Self.now, calendar: AggregationTests.calendar))
        #expect(updates.last?.coverage.isComplete == true)
        #expect(startOfToday < Self.now)
    }
}

/// The phases of a cold-to-warm refresh, drawn at the island page's content width (564 pt) so they can be looked at.
@MainActor @Suite struct StaleSessionRenderTests {
    @Test func rendersEachPhaseOfTheRefresh() throws {
        let recent = [StaleSessionTests.record(minutesAgo: 95), StaleSessionTests.record(minutesAgo: 15)]
        let source = StaleSessionTests.ScriptedSource(
            cached: recent,
            steps: [(recent, StaleSessionTests.now.addingTimeInterval(-60), StaleSessionTests.now.addingTimeInterval(-60))],
            final: recent)
        let updates = try StaleSessionTests.updates(source: source, sampleAge: 20 * 3600)
        let names = ["1-plan-limits-only", "2-cache-limits", "3-cache-snapshot", "4-partial", "5-complete"]
        #expect(updates.count == names.count)
        let calendar = AggregationTests.calendar
        for (update, name) in zip(updates, names) {
            let model = AgentsUsageModel(settings: AgentsSettings(store: WindowTests.FakeStore()), sources: [], calendar: calendar,
                                         clock: { StaleSessionTests.now })
            model.preload(snapshot: update.snapshot ?? UsageSnapshot(), limits: update.limits, plan: .max5x,
                          status: update.snapshot == nil ? .loading : .ready, hasLoaded: update.snapshot != nil,
                          coverage: update.coverage, isRefreshing: !update.isFinal)
            let page = AgentsPage(model: model, live: PageSnapshotTests.live([]), isLive: false)
            let url = OffscreenRender.png(page.page, width: 564, name: "stale-session-\(name)", settle: 0.6)
            #expect(url != nil)
        }
    }
}
