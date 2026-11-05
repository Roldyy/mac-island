import Foundation

/// A paste is requested on main, but the pasteboard work behind it runs on the `GeneralPasteboardLane`, which can be
/// stuck for minutes behind an app that promised pasteboard data and hangs. If the lane frees up late, the key (or the
/// text) must not land in whatever app is in front by then. The request records the time and the front app; the
/// completion asks `isStale`. Pure: the clock and the pid are passed in, so tests drive both.
public struct StalePasteGuard: Equatable, Sendable {
    /// Older than this, the user has moved on. Generous on purpose: a big Excel range or a Universal Clipboard item
    /// delivers its text only at the first read, and the clock includes the rewrite's own read. "The user moved on" is
    /// caught by the front-app check, not by the age.
    public static let maxAge: TimeInterval = 8

    public let requestedAt: TimeInterval
    public let frontPID: pid_t?

    public init(requestedAt: TimeInterval, frontPID: pid_t?) {
        self.requestedAt = requestedAt
        self.frontPID = frontPID
    }

    /// A monotonic clock that does not jump with the wall clock.
    public static func uptime() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    public func isStale(now: TimeInterval, frontPID current: pid_t?) -> Bool {
        if now - requestedAt > Self.maxAge { return true }
        return current != frontPID
    }
}
