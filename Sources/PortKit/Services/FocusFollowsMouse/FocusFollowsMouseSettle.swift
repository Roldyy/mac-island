// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

/// The three preferences a mouse move needs, read once when the service starts and again when they change,
/// never on a move (a `UserDefaults` read per move at the pointer's rate is a cost for nothing).
struct FocusFollowsMousePreferences {
    private let read: () -> (raise: Bool, waitForStop: Bool, delayMilliseconds: Int)
    private(set) var raise = true
    private(set) var waitForStop = true
    private(set) var delayMilliseconds = FocusFollowsMouseSupport.defaultDelayMilliseconds

    init(read: @escaping () -> (raise: Bool, waitForStop: Bool, delayMilliseconds: Int)) {
        self.read = read
        refresh()
    }

    mutating func refresh() {
        let values = read()
        raise = values.raise
        waitForStop = values.waitForStop
        delayMilliseconds = FocusFollowsMouseSupport.sanitizedDelay(values.delayMilliseconds)
    }

    /// Raising always waits for the pointer to stop, so windows passed on the way are not reshuffled. Without a
    /// raise, the user may instead have the delay count time over a window while the pointer moves.
    var waitsForStop: Bool { raise || waitForStop }
}

/// When to wake up to look at a pointer that may have settled: one one-shot timer for the whole wait, set for
/// the full delay and, if the pointer moved meanwhile, set again for what is left. It replaces a 50 ms
/// repeating timer that ran for as long as a movement was pending. Also caps move processing at 20 Hz.
struct FocusFollowsMouseSettle {
    enum Outcome: Equatable {
        case idle
        case rearm(TimeInterval)
        case evaluate
    }

    static let moveInterval: TimeInterval = 0.05
    static let retryInterval: TimeInterval = 0.25

    private(set) var armed = false
    /// Timers created so far (tests and diagnostics).
    private(set) var armCount = 0
    private var lastProcessedAt = -TimeInterval.infinity

    /// False for a move that follows the previous processed one by less than `moveInterval`: the caller keeps
    /// the latest point and the settle timer picks it up.
    mutating func shouldProcessMove(at now: TimeInterval) -> Bool {
        guard now - lastProcessedAt >= Self.moveInterval else { return false }
        lastProcessedAt = now
        return true
    }

    /// Seconds to wait before the one-shot timer fires, or nil when none is needed (nothing pending, or one is
    /// already armed).
    mutating func armIfNeeded(state: FocusFollowsMouseState, now: TimeInterval, delayMilliseconds: Int) -> TimeInterval? {
        guard state.hasPendingEvaluation, !armed else { return nil }
        armed = true
        armCount += 1
        return max(0, remaining(state, now, delayMilliseconds))
    }

    /// The timer fired: evaluate, wait for what is left of the delay, or do nothing.
    mutating func fired(state: FocusFollowsMouseState, now: TimeInterval, delayMilliseconds: Int) -> Outcome {
        armed = false
        guard state.hasPendingEvaluation else { return .idle }
        let left = remaining(state, now, delayMilliseconds)
        guard left > 0 else { return .evaluate }
        armed = true
        armCount += 1
        return .rearm(left)
    }

    /// A button or a key was held when the pointer settled: look again a little later.
    mutating func retry() -> TimeInterval {
        armed = true
        armCount += 1
        return Self.retryInterval
    }

    mutating func reset() {
        armed = false
    }

    private func remaining(_ state: FocusFollowsMouseState, _ now: TimeInterval, _ delayMilliseconds: Int) -> TimeInterval {
        state.movedAt + Double(FocusFollowsMouseSupport.sanitizedDelay(delayMilliseconds)) / 1_000 - now
    }
}
