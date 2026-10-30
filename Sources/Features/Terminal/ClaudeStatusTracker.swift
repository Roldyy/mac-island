import Foundation

/// Pure state machine behind `ClaudeStatus`. The clock is injected so every transition is testable.
///
/// - not running: `.idle`, or `.done` for `doneDuration` seconds right after a run ended
/// - running, output within `workingWindow` seconds: `.working`
/// - running, quiet for longer: `.waiting`
struct ClaudeStatusTracker {
    static let workingWindow: TimeInterval = 2
    static let doneDuration: TimeInterval = 10

    private let clock: () -> Date
    private var wasRunning = false
    private var endedAt: Date?

    init(clock: @escaping () -> Date = Date.init) {
        self.clock = clock
    }

    mutating func update(claudeRunning: Bool, lastOutputAt: Date) -> ClaudeStatus {
        let now = clock()
        if claudeRunning {
            wasRunning = true
            endedAt = nil
            return now.timeIntervalSince(lastOutputAt) <= Self.workingWindow ? .working : .waiting
        }
        if wasRunning {
            wasRunning = false
            endedAt = now
        }
        if let endedAt, now.timeIntervalSince(endedAt) < Self.doneDuration {
            return .done
        }
        endedAt = nil
        return .idle
    }
}
