import IslandKit
import Foundation

/// Reads and writes the preference keys of the Display lane in the app's defaults suite.
/// Migrated from the old app (name kept): `autoQuitEnabled`. (`brightnessControlEnabled` is read by the ported
/// brightness feature now.) The old domain holds no auto-quit delay and no exclusion list, so the three keys
/// below are new and carry safe defaults.
struct DisplaySettings {
    static let suiteName = "be.roldy.macisland"
    static let autoQuitEnabledKey = "autoQuitEnabled"
    /// New key: minutes without a visible window before an app is announced for quitting.
    static let delayKey = "autoQuitDelayMinutes"
    /// New key: bundle ids that are never quit, on top of the built-in list.
    static let excludedKey = "autoQuitExcludedBundleIDs"
    /// New key: while true the tab announces what would be quit but nothing is terminated.
    static let dryRunKey = "autoQuitDryRun"

    static let defaultDelayMinutes = 30
    static let maxDelayMinutes = 24 * 60

    var defaults: UserDefaults

    init(defaults: UserDefaults = AppDefaults.make() ?? .standard) {
        self.defaults = defaults
    }

    /// Absent means off: a fresh install never quits anything on its own.
    var autoQuitEnabled: Bool {
        get { (defaults.object(forKey: Self.autoQuitEnabledKey) as? Bool) ?? false }
        set { defaults.set(newValue, forKey: Self.autoQuitEnabledKey) }
    }

    var autoQuitDelayMinutes: Int {
        get {
            guard let n = (defaults.object(forKey: Self.delayKey) as? NSNumber)?.intValue else {
                return Self.defaultDelayMinutes
            }
            return min(Self.maxDelayMinutes, max(1, n))
        }
        set { defaults.set(min(Self.maxDelayMinutes, max(1, newValue)), forKey: Self.delayKey) }
    }

    /// Absent means dry run: the first real quit needs an explicit choice in the tab.
    var autoQuitDryRun: Bool {
        get { (defaults.object(forKey: Self.dryRunKey) as? Bool) ?? true }
        set { defaults.set(newValue, forKey: Self.dryRunKey) }
    }

    var autoQuitExcludedBundleIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Self.excludedKey) ?? []) }
        set { defaults.set(newValue.sorted(), forKey: Self.excludedKey) }
    }
}
