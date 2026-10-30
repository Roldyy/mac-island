import Foundation

/// Monotonic time source, injected so tests drive time by hand.
public protocol MonotonicClock: Sendable {
    func now() -> TimeInterval
}

/// `ProcessInfo.systemUptime`: monotonic, unaffected by wall-clock changes.
public struct SystemUptimeClock: MonotonicClock {
    public init() {}
    public func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}

/// Heartbeat watchdog of the helper. Armed when manual mode starts; each heartbeat from the owner
/// pushes the deadline; once the deadline passes, `expired` returns true exactly once and the
/// helper restores automatic mode. A heartbeat that arrives after the deadline does not revive it.
public struct Watchdog: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case disarmed
        case armed(deadline: TimeInterval)
    }

    public let timeout: TimeInterval
    public private(set) var state: State = .disarmed

    public init(timeout: TimeInterval) {
        self.timeout = timeout.isFinite && timeout > 0 ? timeout : FanHelperContract.watchdogTimeout
    }

    public var isArmed: Bool { state != .disarmed }

    public mutating func arm(now: TimeInterval) {
        state = .armed(deadline: now + timeout)
    }

    /// True when the deadline moved. False when disarmed or already past the deadline.
    @discardableResult
    public mutating func heartbeat(now: TimeInterval) -> Bool {
        guard case .armed(let deadline) = state, now < deadline else { return false }
        state = .armed(deadline: now + timeout)
        return true
    }

    public mutating func disarm() {
        state = .disarmed
    }

    /// True once when armed and `now` reached the deadline (or is not a number).
    public mutating func expired(now: TimeInterval) -> Bool {
        guard case .armed(let deadline) = state else { return false }
        if now < deadline { return false }   // NaN falls through: expire rather than hang
        state = .disarmed
        return true
    }
}
