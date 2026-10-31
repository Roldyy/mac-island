import Foundation
import Testing
@testable import FinderFeature

@MainActor
private final class FakeCleaningTap: CleaningTapping {
    var onEscape: (Bool, Bool) -> Void = { _, _ in }
    var onLost: () -> Void = {}
    var failure: CleaningStartFailure?
    private(set) var started = 0
    private(set) var stopped = 0
    private(set) var deadline: TimeInterval?
    func start(deadline: TimeInterval) -> CleaningStartFailure? {
        if let failure { return failure }
        started += 1
        self.deadline = deadline
        return nil
    }
    func stop() { stopped += 1 }
}

private final class Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@Suite struct CleaningPolicyTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func runsUntilSixtySeconds() {
        var p = CleaningPolicy(start: t0)
        #expect(p.tick(at: t0.addingTimeInterval(59.9)) == nil)
        #expect(p.tick(at: t0.addingTimeInterval(60)) == .timeout)
        #expect(!p.isRunning)
    }

    @Test func remainingCountsDownAndRoundsUp() {
        let p = CleaningPolicy(start: t0)
        #expect(p.remainingSeconds(at: t0) == 60)
        #expect(p.remainingSeconds(at: t0.addingTimeInterval(15)) == 45)
        #expect(p.remainingSeconds(at: t0.addingTimeInterval(15.2)) == 45)
        #expect(p.remainingSeconds(at: t0.addingTimeInterval(500)) == 0)
        #expect(CleaningPolicy.label(remaining: 45) == "Nettoyage : 45 s")
    }

    @Test func escapeHeldThreeSecondsEnds() {
        var p = CleaningPolicy(start: t0)
        p.escape(down: true, isRepeat: false, at: t0.addingTimeInterval(10))
        p.escape(down: true, isRepeat: true, at: t0.addingTimeInterval(11))  // repeat must not restart the hold
        #expect(p.tick(at: t0.addingTimeInterval(12.9)) == nil)
        #expect(p.tick(at: t0.addingTimeInterval(13)) == .escapeHeld)
    }

    @Test func shortEscapeDoesNotEnd() {
        var p = CleaningPolicy(start: t0)
        p.escape(down: true, isRepeat: false, at: t0.addingTimeInterval(10))
        p.escape(down: false, isRepeat: false, at: t0.addingTimeInterval(11))
        #expect(p.tick(at: t0.addingTimeInterval(20)) == nil)
    }

    @Test func firstReasonWins() {
        var p = CleaningPolicy(start: t0)
        p.end(.tapFailed)
        p.end(.quit)
        #expect(p.tick(at: t0.addingTimeInterval(100)) == .tapFailed)
    }

    @Test func tapDeadlineLetsInputThrough() {
        #expect(CleaningPolicy.swallows(uptime: 99, deadline: 100))
        #expect(!CleaningPolicy.swallows(uptime: 100, deadline: 100))
    }
}

@Suite @MainActor struct CleaningSessionTests {
    private func make() -> (CleaningSession, FakeCleaningTap, Clock, CleanBox<[CleaningEnd]>, CleanBox<[Int]>) {
        let tap = FakeCleaningTap(), clock = Clock()
        let ends = CleanBox<[CleaningEnd]>([]), ticks = CleanBox<[Int]>([])
        let s = CleaningSession(tap: tap, clock: { clock.now }, uptime: { 500 }, runsTimer: false)
        s.onEnd = { ends.value.append($0) }
        s.onTick = { ticks.value.append($0) }
        return (s, tap, clock, ends, ticks)
    }

    @Test func endsAtSixtySecondsAndReleasesTheTap() {
        let (s, tap, clock, ends, ticks) = make()
        #expect(s.start() == nil)
        #expect(tap.deadline == 560)
        #expect(ticks.value == [60])
        clock.advance(15); s.tick()
        #expect(ticks.value.last == 45)
        clock.advance(44); s.tick()
        #expect(ends.value.isEmpty && tap.stopped == 0)
        clock.advance(1); s.tick()
        #expect(ends.value == [.timeout] && tap.stopped == 1 && !s.isRunning)
        s.tick()
        #expect(ends.value == [.timeout])
    }

    @Test func endsWhenEscapeIsHeldThreeSeconds() {
        let (s, tap, clock, ends, _) = make()
        _ = s.start()
        clock.advance(5)
        tap.onEscape(true, false)
        clock.advance(2.9); s.tick()
        #expect(ends.value.isEmpty)
        clock.advance(0.1); s.tick()
        #expect(ends.value == [.escapeHeld] && tap.stopped == 1)
    }

    @Test func tapFailureEndsAtOnce() {
        let (s, tap, _, ends, _) = make()
        _ = s.start()
        tap.onLost()
        #expect(ends.value == [.tapFailed] && tap.stopped == 1)
    }

    @Test func quitEndsAndIsIdempotent() {
        let (s, tap, _, ends, _) = make()
        _ = s.start()
        s.end(.quit); s.end(.quit)
        #expect(ends.value == [.quit] && tap.stopped == 1)
    }

    @Test func missingPermissionStartsNothing() {
        let (s, tap, _, ends, ticks) = make()
        tap.failure = .needsAccessibility
        #expect(s.start() == .needsAccessibility)
        #expect(!s.isRunning && ends.value.isEmpty && ticks.value.isEmpty && tap.started == 0)
    }
}

private final class CleanBox<T>: @unchecked Sendable { var value: T; init(_ v: T) { value = v } }
