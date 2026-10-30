import Foundation

/// Lets a repeated event through at most once per `interval` (monotonic seconds). The helper
/// uses it so a restore the SMC keeps refusing is logged every 10 s, not on every 1 s tick.
public struct LogThrottle: Equatable, Sendable {
    public let interval: TimeInterval
    private var lastAllowed: TimeInterval?

    public init(interval: TimeInterval) { self.interval = interval }

    /// True the first time, then once `interval` has passed since the last true. A clock that
    /// went backwards lets the event through rather than silencing it.
    public mutating func allow(now: TimeInterval) -> Bool {
        if let last = lastAllowed, now >= last, now - last < interval { return false }
        lastAllowed = now
        return true
    }

    /// The next event goes through (the condition cleared).
    public mutating func reset() { lastAllowed = nil }
}
