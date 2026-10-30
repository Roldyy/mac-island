import Foundation

/// Pure decision: should the mouse be nudged now? No clock, no CGEvent in here.
struct JiggleScheduler: Equatable {
    /// Seconds. At least one minute.
    let interval: TimeInterval
    private(set) var lastJiggle: Date?

    init(intervalMinutes: Int) {
        interval = TimeInterval(max(1, intervalMinutes)) * 60
    }

    func shouldJiggle(now: Date, idleSeconds: TimeInterval, keepAwakeActive: Bool, enabled: Bool) -> Bool {
        guard keepAwakeActive, enabled, idleSeconds >= interval else { return false }
        if let lastJiggle, now.timeIntervalSince(lastJiggle) < interval { return false }
        return true
    }

    mutating func didJiggle(at now: Date) { lastJiggle = now }
    mutating func reset() { lastJiggle = nil }
}
