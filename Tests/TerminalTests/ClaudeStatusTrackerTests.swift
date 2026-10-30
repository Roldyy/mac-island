import Foundation
import Testing
@testable import TerminalFeature

@Suite struct ClaudeStatusTrackerTests {
    final class Clock { var now = Date(timeIntervalSince1970: 1_000) }

    private func make() -> (ClaudeStatusTracker, Clock) {
        let clock = Clock()
        return (ClaudeStatusTracker(clock: { clock.now }), clock)
    }

    @Test func idleWhenNeverRan() {
        var (t, clock) = make()
        #expect(t.update(claudeRunning: false, lastOutputAt: clock.now) == .idle)
    }

    @Test func workingWithRecentOutput() {
        var (t, clock) = make()
        #expect(t.update(claudeRunning: true, lastOutputAt: clock.now) == .working)
        clock.now += 2
        #expect(t.update(claudeRunning: true, lastOutputAt: clock.now - 2) == .working)
    }

    @Test func waitingWhenQuietLongerThanTwoSeconds() {
        var (t, clock) = make()
        let last = clock.now
        clock.now += 2.5
        #expect(t.update(claudeRunning: true, lastOutputAt: last) == .waiting)
    }

    @Test func backToWorkingOnNewOutput() {
        var (t, clock) = make()
        let last = clock.now
        clock.now += 5
        #expect(t.update(claudeRunning: true, lastOutputAt: last) == .waiting)
        #expect(t.update(claudeRunning: true, lastOutputAt: clock.now) == .working)
    }

    @Test func doneForTenSecondsThenIdle() {
        var (t, clock) = make()
        _ = t.update(claudeRunning: true, lastOutputAt: clock.now)
        clock.now += 1
        #expect(t.update(claudeRunning: false, lastOutputAt: clock.now) == .done)
        clock.now += 9
        #expect(t.update(claudeRunning: false, lastOutputAt: clock.now) == .done)
        clock.now += 1.5
        #expect(t.update(claudeRunning: false, lastOutputAt: clock.now) == .idle)
        clock.now += 100
        #expect(t.update(claudeRunning: false, lastOutputAt: clock.now) == .idle)
    }

    @Test func newRunCancelsDone() {
        var (t, clock) = make()
        _ = t.update(claudeRunning: true, lastOutputAt: clock.now)
        #expect(t.update(claudeRunning: false, lastOutputAt: clock.now) == .done)
        #expect(t.update(claudeRunning: true, lastOutputAt: clock.now) == .working)
    }
}
