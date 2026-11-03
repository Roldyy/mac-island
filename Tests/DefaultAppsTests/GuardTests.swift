import Foundation
import IslandTestSupport
import Testing
@testable import DefaultAppsFeature

/// A clock the test moves by hand.
final class TestClock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}

@MainActor
@Suite struct GuardTests {
    let bench = TestDefaults.make()
    let ls = Fixture.world()
    let clock = TestClock()
    let lines = LogLines()

    func make(enabled: Bool = true) -> (guard: DefaultAppsGuard, choices: DefaultAppsChoicesStore, settings: DefaultAppsSettings) {
        let settings = DefaultAppsSettings(defaults: bench.defaults)
        settings.guardEnabled = enabled
        let choices = DefaultAppsChoicesStore(defaults: bench.defaults)
        let clock = clock, lines = lines
        let keeper = DefaultAppsGuard(settings: settings, choices: choices, launchServices: ls,
                                      now: { clock.date }, log: { lines.add($0) })
        return (keeper, choices, settings)
    }

    func choose(_ choices: DefaultAppsChoicesStore, _ id: String = "public.json", explicit: Bool = false, kind: ChangeKind = .contentType) {
        choices.upsert(StoredChoice(kind: kind, identifier: id, bundleID: Fixture.sublime, explicitlyPicked: explicit))
    }

    @Test func isOffByDefaultAndDoesNothingWhileOff() async {
        defer { bench.cleanup() }
        #expect(DefaultAppsSettings(defaults: bench.defaults).guardEnabled == false)
        let g = make(enabled: false)
        choose(g.choices)
        #expect(await g.guard.check(reason: "launch").isEmpty && ls.writes.isEmpty)
    }

    @Test func reappliesAChoiceThatMacOSResetAndLogsIt() async {
        defer { bench.cleanup() }
        let g = make()
        choose(g.choices)
        let actions = await g.guard.check(reason: "launch")
        #expect(actions == [.reapplied("contentType:public.json")])
        #expect(ls.handlers["public.json"] == Fixture.sublime)
        #expect(lines.all.contains { $0.contains("guard(launch)") && $0.contains("public.json") })
    }

    @Test func aChoiceThatStillHoldsCostsNoWrite() async {
        defer { bench.cleanup() }
        let g = make()
        choose(g.choices)
        ls.handlers["public.json"] = Fixture.sublime
        #expect(await g.guard.check(reason: "activation").isEmpty && ls.writes.isEmpty)
    }

    @Test func neverMoreThanOncePerHourPerType() async {
        defer { bench.cleanup() }
        let g = make()
        choose(g.choices)
        _ = await g.guard.check(reason: "launch")
        ls.handlers["public.json"] = Fixture.textEdit            // macOS resets it again
        clock.advance(600)
        #expect(await g.guard.check(reason: "activation") == [.rateLimited("contentType:public.json")])
        clock.advance(2990)                                       // 3590 s after the first attempt
        #expect(await g.guard.check(reason: "activation") == [.rateLimited("contentType:public.json")])
        clock.advance(40)                                         // past the hour and past the 30 s debounce
        #expect(await g.guard.check(reason: "activation") == [.reapplied("contentType:public.json")])
        #expect(ls.writes.count == 2)
    }

    @Test func aFailingTypeIsAlsoTriedAtMostOncePerHour() async {
        defer { bench.cleanup() }
        let g = make()
        choose(g.choices)
        ls.failing = ["public.json"]
        #expect(await g.guard.check(reason: "launch") == [.failed("contentType:public.json")])
        clock.advance(60)
        #expect(await g.guard.check(reason: "activation") == [.rateLimited("contentType:public.json")])
        #expect(ls.writes.count == 1)
    }

    @Test func theAttemptTimeIsWrittenBeforeTheCall() async {
        defer { bench.cleanup() }
        let g = make()
        choose(g.choices)
        let choices = g.choices
        let stamp = Seen()
        ls.beforeWrite = { _, id in stamp.record(id: id, planned: choices.lastAttempt(for: "contentType:\(id)") != nil) }
        _ = await g.guard.check(reason: "launch")
        #expect(stamp.first == [true])
    }

    @Test func checksCloserThanTheDebounceAreOne() async {
        defer { bench.cleanup() }
        let g = make()
        choose(g.choices)
        ls.failing = ["public.json"]
        _ = await g.guard.check(reason: "launch")
        clock.advance(5)
        #expect(await g.guard.check(reason: "activation").isEmpty)
    }

    @Test func aProtectedChoiceNobodyPickedOnPurposeIsNeverReapplied() async {
        defer { bench.cleanup() }
        let g = make()
        choose(g.choices, "public.folder")
        choose(g.choices, "http", kind: .scheme)
        let actions = await g.guard.check(reason: "launch")
        #expect(actions == [.skipped("contentType:public.folder"), .skipped("scheme:http")] && ls.writes.isEmpty)
        choose(g.choices, "http", explicit: true, kind: .scheme)
        clock.advance(60)
        #expect(await g.guard.check(reason: "activation").contains(.reapplied("scheme:http")))
    }

    @Test func aChoiceWhoseAppIsGoneIsSkippedNotFailed() async {
        defer { bench.cleanup() }
        let g = make()
        g.choices.upsert(StoredChoice(kind: .contentType, identifier: "public.json", bundleID: "gone.app", explicitlyPicked: false))
        #expect(await g.guard.check(reason: "launch") == [.skipped("contentType:public.json")] && ls.writes.isEmpty)
    }

    @Test func callsAreSerialisedAndThreeFailuresStopThePass() async {
        defer { bench.cleanup() }
        let g = make()
        for id in ["public.json", "public.rtf", "public.plain-text", "public.swift-source"] { choose(g.choices, id) }
        ls.failing = ["public.json", "public.rtf", "public.plain-text", "public.swift-source"]
        ls.delay = .milliseconds(3)
        _ = await g.guard.check(reason: "launch")
        #expect(ls.writes.count == 3 && ls.peak == 1)
    }

    @Test func switchingTheGuardOffMidRunStopsIt() async {
        defer { bench.cleanup() }
        let g = make()
        for id in ["public.json", "public.rtf"] { choose(g.choices, id) }
        let settings = g.settings
        ls.beforeWrite = { _, _ in Task { @MainActor in settings.guardEnabled = false } }
        ls.delay = .milliseconds(30)
        _ = await g.guard.check(reason: "launch")
        #expect(ls.writes.count <= 2)
    }
}

final class LogLines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func add(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return lines }
}
