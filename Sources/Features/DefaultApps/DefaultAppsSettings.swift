import Foundation
import Observation

/// The feature's one preference: the opt-in guard. Off until the user switches it on.
@MainActor @Observable
public final class DefaultAppsSettings {
    public static let guardKey = "defaultAppsGuardEnabled"

    public var guardEnabled: Bool {
        didSet { defaults.set(guardEnabled, forKey: Self.guardKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        guardEnabled = defaults.bool(forKey: Self.guardKey)
    }
}
