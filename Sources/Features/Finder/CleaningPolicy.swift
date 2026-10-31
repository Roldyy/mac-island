import Foundation

/// Why cleaning mode ended.
enum CleaningEnd: Equatable, Sendable {
    case timeout, escapeHeld, tapFailed, quit, cancelled
}

/// Pure timing and exit rules of cleaning mode. It ends at 60 s, after Escape was held 3 s, or when the
/// tap fails or the app quits: input is never swallowed without one of these coming.
struct CleaningPolicy: Equatable, Sendable {
    static let maxDuration: TimeInterval = 60
    static let escapeHold: TimeInterval = 3
    static let escapeKeyCode = 53

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

    static func label(remaining: Int) -> String { "Nettoyage : \(remaining) s" }

    /// Last line of defence, used by the tap callback itself (its own thread, monotonic clock): even if the
    /// main thread stalls, input flows again once the deadline passed.
    static func swallows(uptime: TimeInterval, deadline: TimeInterval) -> Bool { uptime < deadline }
}
