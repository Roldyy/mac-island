import Foundation
import IslandKit
import Testing
@testable import AgentsFeature

@Suite struct PlanLimitTests {
    static let now = AggregationTests.date("2026-10-21T14:30:00Z")

    static func file(_ samples: String) -> Data { Data(#"{"version":1,"samples":[\#(samples)]}"#.utf8) }

    static func sample(t: Int, fh: Int, sd: Int, xu: Int = 0) -> String {
        #"{"t":\#(t),"org":"x","u":{"fh":\#(fh),"sd":\#(sd),"xu":\#(xu)}}"#
    }

    // MARK: parsing

    @Test func takesTheNewestSampleWhateverTheOrder() {
        let data = Self.file(Self.sample(t: 1_793_449_432, fh: 7, sd: 8) + "," + Self.sample(t: 1_793_449_000, fh: 1, sd: 2))
        let latest = PlanLimitParser.latest(from: data)
        #expect(latest?.fiveHour == 7 && latest?.sevenDay == 8)
    }

    @Test func millisecondAndSecondTimestampsGiveTheSameInstant() {
        let seconds = PlanLimitParser.latest(from: Self.file(Self.sample(t: 1_793_449_432, fh: 1, sd: 1)))
        let millis = PlanLimitParser.latest(from: Self.file(Self.sample(t: 1_793_449_432_809, fh: 1, sd: 1)))
        #expect(seconds?.date == Date(timeIntervalSince1970: 1_793_449_432))
        #expect(abs((millis?.date.timeIntervalSince1970 ?? 0) - 1_793_449_432.809) < 0.001)
    }

    @Test func outOfRangeOrFractionalValuesAreUnknownNotClamped() {
        let data = Data(#"{"samples":[{"t":1793449432,"u":{"fh":140,"sd":-3,"xu":12.5}}]}"#.utf8)
        let s = PlanLimitParser.latest(from: data)
        #expect(s != nil)
        #expect(s?.fiveHour == nil && s?.sevenDay == nil && s?.extraUsage == nil)
        #expect(s?.hasAnyValue == false)
        let edge = PlanLimitParser.latest(from: Self.file(Self.sample(t: 1_793_449_432, fh: 0, sd: 100)))
        #expect(edge?.fiveHour == 0 && edge?.sevenDay == 100)
    }

    @Test func wrongTypesAreUnknown() {
        let data = Data(#"{"samples":[{"t":1793449432,"u":{"fh":"50","sd":true,"xu":null}}]}"#.utf8)
        let s = PlanLimitParser.latest(from: data)
        #expect(s?.fiveHour == nil && s?.sevenDay == nil && s?.extraUsage == nil)
    }

    @Test func malformedOrEmptyFilesGiveNothing() {
        #expect(PlanLimitParser.latest(from: Data("not json".utf8)) == nil)
        #expect(PlanLimitParser.latest(from: Data("[]".utf8)) == nil)
        #expect(PlanLimitParser.latest(from: Data(#"{"samples":[]}"#.utf8)) == nil)
        #expect(PlanLimitParser.latest(from: Data(#"{"samples":[{"u":{"fh":1}}]}"#.utf8)) == nil)   // no t
        #expect(PlanLimitParser.latest(from: Data(#"{"samples":[{"t":0,"u":{"fh":1}}]}"#.utf8)) == nil)
    }

    @Test func missingFileGivesNothing() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-\(UUID().uuidString).json")
        #expect(PlanLimitSource(url: url).load() == nil)
    }

    @Test func readsAFileFromDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("limits-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Self.file(Self.sample(t: 1_793_449_432_809, fh: 3, sd: 58, xu: 100)).write(to: url)
        let s = PlanLimitSource(url: url).load()
        #expect(s?.fiveHour == 3 && s?.sevenDay == 58 && s?.extraUsage == 100)
    }

    // MARK: staleness

    @Test func aSampleOlderThanFifteenMinutesIsStale() {
        let fresh = PlanLimitSample(date: Self.now.addingTimeInterval(-14 * 60), fiveHour: 1)
        let stale = PlanLimitSample(date: Self.now.addingTimeInterval(-16 * 60), fiveHour: 1)
        let future = PlanLimitSample(date: Self.now.addingTimeInterval(60), fiveHour: 1)
        #expect(!fresh.isStale(at: Self.now) && stale.isStale(at: Self.now) && !future.isStale(at: Self.now))
    }

    // MARK: pace marker

    @Test func paceIsTheElapsedShareOfTheWindowClamped() {
        let start = Self.now.addingTimeInterval(-2 * 3600)
        let end = start.addingTimeInterval(5 * 3600)
        #expect(abs((LimitsState.elapsedFraction(now: Self.now, start: start, end: end) ?? 0) - 0.4) < 1e-9)
        #expect(LimitsState.elapsedFraction(now: start.addingTimeInterval(-60), start: start, end: end) == 0)
        #expect(LimitsState.elapsedFraction(now: end.addingTimeInterval(60), start: start, end: end) == 1)
        #expect(LimitsState.elapsedFraction(now: Self.now, start: end, end: start) == nil)
    }

    @Test func markerFollowsTheDisplayedDirection() {
        let row = LimitRow(kind: .session, usedPercent: 30, elapsed: 0.4)
        #expect(row.fill(.used) == 0.3 && row.paceMarker(.used) == 0.4)
        #expect(abs((row.fill(.remaining) ?? 0) - 0.7) < 1e-9 && abs((row.paceMarker(.remaining) ?? 0) - 0.6) < 1e-9)
        #expect(LimitRow(kind: .weekly, usedPercent: 30).paceMarker(.used) == nil)
    }

    @Test func valueTextUsesTheParityWording() {
        let row = LimitRow(kind: .session, usedPercent: 42)
        #expect(row.valueText(.used) == "42\u{202F}% utilisé")
        #expect(row.valueText(.remaining) == "58\u{202F}% restant")
        #expect(LimitRow(kind: .session, usedPercent: nil).valueText(.used) == nil)
    }

    // MARK: resolving

    static var block: UsageBlock {
        let start = AggregationTests.date("2026-10-21T12:00:00Z")
        return UsageBlock(start: start, end: start.addingTimeInterval(5 * 3600),
                          lastActivity: AggregationTests.date("2026-10-21T14:00:00Z"), tokens: 900, cost: 1, estimated: false)
    }

    @Test func fileSampleGivesPercentagesAndTakesTheSessionBoundsFromTheBlock() {
        let sample = PlanLimitSample(date: Self.now.addingTimeInterval(-60), fiveHour: 40, sevenDay: 60, extraUsage: 100)
        let state = LimitsState.resolve(sample: sample, block: Self.block, weekTokens: 5, now: Self.now)
        #expect(state.source == .planFile && !state.isStale)
        #expect(state.rows.map(\.kind) == [.session, .weekly])
        #expect(state.rows[0].usedPercent == 40 && state.rows[0].renewal == Self.block.end)
        #expect(abs((state.rows[0].elapsed ?? 0) - 0.5) < 1e-9)
        #expect(state.rows[1].usedPercent == 60 && state.rows[1].elapsed == nil && state.rows[1].renewal == nil)
    }

    @Test func aStaleSampleIsFlagged() {
        let sample = PlanLimitSample(date: Self.now.addingTimeInterval(-3600), fiveHour: 40, sevenDay: nil)
        let state = LimitsState.resolve(sample: sample, block: nil, weekTokens: 0, now: Self.now)
        #expect(state.isStale && state.rows.map(\.kind) == [.session])
    }

    @Test func withoutAFileTheBlockIsEstimatedAndNeverGetsAPercentage() {
        for sample in [nil, PlanLimitSample(date: Self.now, fiveHour: nil, sevenDay: nil)] {
            let state = LimitsState.resolve(sample: sample, block: Self.block, weekTokens: 12_345, now: Self.now)
            #expect(state.source == .estimatedFromLogs)
            #expect(state.rows.allSatisfy { $0.usedPercent == nil })
            #expect(state.rows[0].tokens == 900 && state.rows[1].tokens == 12_345)
        }
    }

    @Test func nothingKnownMeansTheWaitingState() {
        let state = LimitsState.resolve(sample: nil, block: nil, weekTokens: 0, now: Self.now)
        #expect(state.source == .none && state.rows.isEmpty)
        let over = LimitsState.resolve(sample: nil, block: Self.block, weekTokens: 0, now: Self.now.addingTimeInterval(6 * 3600))
        #expect(over.source == .none)
    }

    @Test func focusPicksTheRightLimit() {
        let state = LimitsState(rows: [LimitRow(kind: .session, usedPercent: 30), LimitRow(kind: .weekly, usedPercent: 70)],
                                source: .planFile)
        #expect(state.focused(.mostUsed)?.kind == .weekly)
        #expect(state.focused(.session)?.usedPercent == 30)
        #expect(state.focused(.weekly)?.usedPercent == 70)
        let estimated = LimitsState(rows: [LimitRow(kind: .session, usedPercent: nil, tokens: 5)], source: .estimatedFromLogs)
        #expect(estimated.focused(.mostUsed) == nil && estimated.focused(.session) == nil)
    }

    // MARK: closed island

    @Test func restingActivityShowsTheFocusedLimitInTheChosenDirection() {
        let state = LimitsState(rows: [LimitRow(kind: .session, usedPercent: 92), LimitRow(kind: .weekly, usedPercent: 10)],
                                source: .planFile)
        let used = AgentsRestingActivity.activity(limits: state, focus: .mostUsed, display: .used)
        #expect(used?.id == "agents.resting" && used?.source == "agents" && used?.priority == .ambient)
        #expect(used?.leading?.symbol == "gauge" && used?.leading?.text == "92\u{202F}%" && used?.leading?.status == .danger)
        let left = AgentsRestingActivity.activity(limits: state, focus: .weekly, display: .remaining)
        #expect(left?.leading?.text == "90\u{202F}%" && left?.leading?.status == .neutral)
        #expect(AgentsRestingActivity.activity(limits: LimitsState(), focus: .mostUsed, display: .used) == nil)
    }

    @MainActor final class Recorder: AgentsActivityPosting {
        var posted: [IslandActivity] = []
        var withdrawn: [String] = []
        func post(_ activity: IslandActivity) { posted.append(activity) }
        func withdraw(id: String) { withdrawn.append(id) }
    }

    @Test @MainActor func controllerPostsOnlyWhenTheIdleContentIsAgents() async throws {
        let store = WindowTests.FakeStore()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rest-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Self.file(Self.sample(t: 1_793_449_432_809, fh: 20, sd: 50)).write(to: url)
        let recorder = Recorder()
        let controller = AgentsRestingController(settings: AgentsSettings(store: store), limitSource: PlanLimitSource(url: url),
                                                 poster: recorder, clock: { Date(timeIntervalSince1970: 1_793_449_500) })
        await controller.refresh()
        #expect(recorder.posted.isEmpty && recorder.withdrawn == ["agents.resting"])
        store.values["notchIdleContent"] = "agents"
        await controller.refresh()
        #expect(recorder.posted.count == 1)
        #expect(recorder.posted.first?.leading?.text == "50\u{202F}%")   // most used = weekly (50 % used), shown as what is left
    }
}
