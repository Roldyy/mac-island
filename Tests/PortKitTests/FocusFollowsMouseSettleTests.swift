import CoreGraphics
import Foundation
import Testing
@testable import PortKit

/// Focus follows mouse must cost nothing per mouse move: preferences are read once, not per move, and the
/// settle wait is a one-shot timer (re-armed for the remaining time), not a 20 Hz repeating one.
@Suite struct FocusFollowsMouseSettleTests {
    @Test func preferencesAreReadOnceNotPerMove() {
        var reads = 0
        var cache = FocusFollowsMousePreferences { reads += 1; return (raise: false, waitForStop: true, delayMilliseconds: 400) }
        #expect(reads == 1, "read at start")
        for _ in 0..<200 {
            #expect(cache.waitsForStop)
            #expect(cache.delayMilliseconds == 400)
        }
        #expect(reads == 1, "no read on a move")
        cache.refresh()
        #expect(reads == 2, "re-read on a change notification only")
    }

    @Test func waitsForStopWhenRaisingOrWhenAskedTo() {
        #expect(FocusFollowsMousePreferences { (raise: true, waitForStop: false, delayMilliseconds: 250) }.waitsForStop)
        #expect(FocusFollowsMousePreferences { (raise: false, waitForStop: true, delayMilliseconds: 250) }.waitsForStop)
        #expect(!FocusFollowsMousePreferences { (raise: false, waitForStop: false, delayMilliseconds: 250) }.waitsForStop)
    }

    @Test func aBurstOfMovesArmsOneTimerAndTheSettleFiresOnce() {
        var state = FocusFollowsMouseState()
        var settle = FocusFollowsMouseSettle()
        var arms: [TimeInterval] = []
        // 100 moves in 200 ms, delay 250 ms.
        for i in 0..<100 {
            let now = Double(i) * 0.002
            state.recordMovement(to: CGPoint(x: Double(i), y: 5), at: now)
            if let wait = settle.armIfNeeded(state: state, now: now, delayMilliseconds: 250) { arms.append(wait) }
        }
        #expect(arms.count == 1, "one timer for the whole burst")
        #expect(abs(arms[0] - 0.25) < 0.001)
        // First fire, 250 ms after the first move: the pointer moved at 198 ms, so wait the remainder.
        guard case .rearm(let rest) = settle.fired(state: state, now: 0.25, delayMilliseconds: 250) else {
            Issue.record("expected a re-arm for the remaining time"); return
        }
        #expect(abs(rest - 0.198) < 0.002)
        #expect(settle.fired(state: state, now: 0.45, delayMilliseconds: 250) == .evaluate)
        #expect(settle.armCount == 2, "at most two timers for a whole settle, never one per tick")
    }

    @Test func nothingPendingArmsNothing() {
        var settle = FocusFollowsMouseSettle()
        #expect(settle.armIfNeeded(state: FocusFollowsMouseState(), now: 1, delayMilliseconds: 250) == nil)
        #expect(settle.armCount == 0)
        #expect(settle.fired(state: FocusFollowsMouseState(), now: 1, delayMilliseconds: 250) == .idle)
    }

    @Test func moveProcessingIsCappedAtTwentyHertz() {
        var settle = FocusFollowsMouseSettle()
        var processed = 0
        for i in 0..<100 where settle.shouldProcessMove(at: Double(i) * 0.005) { processed += 1 }
        #expect(processed <= 11, "100 moves over half a second: at most one every 50 ms")
        #expect(processed >= 9)
    }

    @Test func resetDisarmsSoTheNextMoveArmsAgain() {
        var state = FocusFollowsMouseState()
        var settle = FocusFollowsMouseSettle()
        state.recordMovement(to: .zero, at: 0)
        #expect(settle.armIfNeeded(state: state, now: 0, delayMilliseconds: 250) != nil)
        #expect(settle.armIfNeeded(state: state, now: 0.01, delayMilliseconds: 250) == nil, "already armed")
        settle.reset()
        #expect(settle.armIfNeeded(state: state, now: 0.02, delayMilliseconds: 250) != nil)
    }
}
