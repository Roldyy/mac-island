import Foundation
import Testing
@testable import TerminalFeature

/// Lane 1 (perf): the status model used to hold a 1 s timer for the life of the app. It now ticks only while a
/// shell exists or a "Terminé" is still settling, and a fake timer factory proves it by counting live timers.
@MainActor
@Suite struct ClaudeStatusModelTests {
    final class FakeSource: ClaudeStatusSource {
        var hasSession = false
        var shellPid: pid_t = 0
        var lastOutputAt = Date.distantPast
        var claudeRunning = false
        private(set) var scans = 0
        func containsClaude(below pid: pid_t) -> Bool { scans += 1; return claudeRunning }
    }

    final class FakeTimers {
        private(set) var created = 0
        private(set) var live = 0
        private var handlers: [@MainActor () -> Void] = []
        var factory: ClaudeStatusTimerFactory {
            { [self] _, handler in
                created += 1; live += 1
                handlers.append(handler)
                let index = handlers.count - 1
                return { [self] in live -= 1; handlers[index] = {} }
            }
        }
        @MainActor func tick() { handlers.last?() }
    }

    final class Clock { var now = Date(timeIntervalSince1970: 1_000) }

    private func make(_ source: FakeSource, _ timers: FakeTimers, _ clock: Clock = Clock()) -> (ClaudeStatusModel, NotificationCenter) {
        let center = NotificationCenter()
        let model = ClaudeStatusModel(source: source, makeTimer: timers.factory, center: center,
                                      tracker: ClaudeStatusTracker(clock: { clock.now }))
        return (model, center)
    }

    @Test func noShellNoTimer() {
        let timers = FakeTimers()
        _ = make(FakeSource(), timers)
        #expect(timers.created == 0 && timers.live == 0, "nothing runs for a terminal nobody opened")
    }

    @Test func aShellStartingArmsOneTimerAndNoMoreThanOne() {
        let source = FakeSource(), timers = FakeTimers()
        let (model, center) = make(source, timers)
        source.hasSession = true
        center.post(name: ClaudeStatusModel.sessionChanged, object: nil)
        center.post(name: ClaudeStatusModel.sessionChanged, object: nil)
        #expect(timers.created == 1 && timers.live == 1)
        withExtendedLifetime(model) {}
    }

    @Test func theProcessTreeIsScannedOnlyWhileAShellExists() {
        let source = FakeSource(), timers = FakeTimers()
        let (model, center) = make(source, timers)
        source.hasSession = true
        center.post(name: ClaudeStatusModel.sessionChanged, object: nil)
        timers.tick()
        #expect(source.scans >= 1)
        let scans = source.scans
        source.hasSession = false
        timers.tick()
        #expect(source.scans == scans, "no shell: no scan")
        withExtendedLifetime(model) {}
    }

    @Test func theTimerStopsOnceTheShellIsGoneAndTheDoneBadgeHasSettled() {
        let source = FakeSource(), timers = FakeTimers(), clock = Clock()
        let (model, center) = make(source, timers, clock)
        source.hasSession = true
        source.claudeRunning = true
        source.lastOutputAt = clock.now
        center.post(name: ClaudeStatusModel.sessionChanged, object: nil)
        #expect(model.status == .working)
        // The shell exits while Claude was running: "Terminé" shows for ten seconds, so the timer still runs.
        source.hasSession = false
        center.post(name: ClaudeStatusModel.sessionChanged, object: nil)
        #expect(model.status == .done && timers.live == 1)
        clock.now += ClaudeStatusTracker.doneDuration + 1
        timers.tick()
        #expect(model.status == .idle && timers.live == 0, "settled on idle, no shell: the timer ends")
    }

    @Test func aShellThatRestartsArmsAgain() {
        let source = FakeSource(), timers = FakeTimers()
        let (model, center) = make(source, timers)
        source.hasSession = true
        center.post(name: ClaudeStatusModel.sessionChanged, object: nil)
        source.hasSession = false
        center.post(name: ClaudeStatusModel.sessionChanged, object: nil)
        #expect(timers.live == 0)
        source.hasSession = true
        center.post(name: ClaudeStatusModel.sessionChanged, object: nil)
        #expect(timers.created == 2 && timers.live == 1)
        withExtendedLifetime(model) {}
    }
}
