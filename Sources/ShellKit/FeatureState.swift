import IslandKit

/// What the registry says about one feature right now. The first match in `FeatureRegistry.state(for:)` wins.
public enum FeatureState: Equatable, Sendable {
    case active
    /// Switched on, waiting for a system permission. Still started: each start() only arms what is granted.
    case needsPermission(FeaturePermission)
    /// The user's switch is off.
    case off
    /// The global kill switch is on.
    case killed
    /// Safe mode keeps only the daily features.
    case safeMode
    /// Left its start flag set on two launches in a row.
    case quarantined
    case unavailable(reason: String)

    /// True when the feature should be started and shown.
    public var isEnabled: Bool {
        switch self {
        case .active, .needsPermission: true
        default: false
        }
    }
}
