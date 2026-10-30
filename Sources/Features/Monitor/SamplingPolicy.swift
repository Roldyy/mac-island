import Foundation

/// How often to sample. 1 Hz at most; slower and only when alerts need it while the island is closed.
enum SamplingCadence {
    static let visibleInterval: TimeInterval = 1
    static let backgroundRange: ClosedRange<TimeInterval> = 5...10

    /// `nil` means: do not sample at all.
    static func interval(visible: Bool, alertsEnabled: Bool, background: TimeInterval) -> TimeInterval? {
        if visible { return visibleInterval }
        guard alertsEnabled else { return nil }
        return min(backgroundRange.upperBound, max(backgroundRange.lowerBound, background))
    }
}

enum NotificationPolicy {
    enum Mode: Equatable { case inIslandOnly, system }

    /// System notifications only from a bundled app, once the user authorized them and asked for them.
    static func mode(hasBundle: Bool, status: NotificationAuthorization, userEnabled: Bool) -> Mode {
        hasBundle && status == .authorized && userEnabled ? .system : .inIslandOnly
    }
}
