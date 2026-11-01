// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

/// Why cleaning mode ended. Every one of these gives the keyboard back at once.
enum CleaningEnd: Equatable {
    /// 60 seconds passed.
    case timeout
    /// Escape was held for three seconds.
    case escapeHeld
    /// The person unlocked it: Escape five times, or the Unlock button.
    case unlocked
    /// The system switched the tap off, or Accessibility was taken away.
    case tapFailed
    /// The app is quitting (`willTerminate`, the app delegate, `stop`).
    case quit
    /// The registry stopped the feature: switch off, kill switch, safe mode, quarantine.
    case stopped
    /// The login session was switched away.
    case sessionLeft
}

/// Pure timing and exit rules of cleaning mode (Mac Island's own, added on top of the upstream five-Escape
/// gesture): input is never swallowed for longer than `maxDuration`, and holding Escape for `escapeHold` seconds
/// always ends it, whatever else is going on.
struct CleaningPolicy: Equatable {
    static let maxDuration: TimeInterval = 60
    static let escapeHold: TimeInterval = 3
    static let escapeKeyCode: Int64 = 53

    let start: Date
    private(set) var escapeDownAt: Date?
    private(set) var ended: CleaningEnd?

    init(start: Date) { self.start = start }

    var isRunning: Bool { ended == nil }

    /// A key repeat never restarts the hold; the key coming up cancels it.
    mutating func escape(down: Bool, isRepeat: Bool, at now: Date) {
        guard isRunning else { return }
        if !down { escapeDownAt = nil; return }
        if escapeDownAt == nil && !isRepeat { escapeDownAt = now }
    }

    /// Call at least every 0.5 s. Returns the end reason once reached, and keeps returning it.
    @discardableResult
    mutating func tick(at now: Date) -> CleaningEnd? {
        guard isRunning else { return ended }
        if now.timeIntervalSince(start) >= Self.maxDuration {
            ended = .timeout
        } else if let down = escapeDownAt, now.timeIntervalSince(down) >= Self.escapeHold {
            ended = .escapeHeld
        }
        return ended
    }

    mutating func end(_ reason: CleaningEnd) { if isRunning { ended = reason } }

    /// Whole seconds left, rounded up, never below 0.
    func remainingSeconds(at now: Date) -> Int {
        let left = Self.maxDuration - now.timeIntervalSince(start)
        return max(0, Int(left.rounded(.up)))
    }

    /// Last line of defence, used by the tap callback itself on the monotonic clock: even if the timer never
    /// fires, input flows again once the deadline passed.
    static func swallows(uptime: TimeInterval, deadline: TimeInterval) -> Bool { uptime < deadline }
}
