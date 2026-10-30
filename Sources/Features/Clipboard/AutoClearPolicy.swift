import Foundation

enum AutoClearPolicy {
    /// nil when the feature is off (delay <= 0).
    static func effectiveDelay(_ seconds: TimeInterval) -> TimeInterval? { seconds > 0 ? seconds : nil }

    /// Only clear what we scheduled for: if the user copied something since, leave it.
    static func shouldClear(expectedChangeCount: Int, currentChangeCount: Int) -> Bool {
        expectedChangeCount == currentChangeCount
    }
}
