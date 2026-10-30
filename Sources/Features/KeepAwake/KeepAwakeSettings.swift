import Foundation

/// Reads the migrated preference keys (old names kept) from the app's defaults suite.
/// Observed in the old app's domain: keepAwakeMouseJiggleEnabled, keepAwakeMouseJiggleIntervalMinutes,
/// notchKeepAwakeActivity (carried by the "notch" prefix), clamshellPreferred and defaultDurationMinutes
/// (both outside the key map's prefixes: not migrated, absent means the default below).
struct KeepAwakeSettings {
    static let suiteName = "be.roldy.macisland"
    /// New key (not migrated): also keep the display awake. The old keepAwakeExternalDisplay is unexplained, so unused.
    static let preventDisplaySleepKey = "keepAwakePreventDisplaySleep"

    let defaults: UserDefaults

    init(defaults: UserDefaults = UserDefaults(suiteName: KeepAwakeSettings.suiteName) ?? .standard) {
        self.defaults = defaults
    }

    var mouseJiggleEnabled: Bool { (defaults.object(forKey: "keepAwakeMouseJiggleEnabled") as? Bool) ?? false }
    var mouseJiggleIntervalMinutes: Int {
        max(1, (defaults.object(forKey: "keepAwakeMouseJiggleIntervalMinutes") as? NSNumber)?.intValue ?? 1)
    }
    /// 0 = no limit.
    var defaultDurationMinutes: Int {
        max(0, (defaults.object(forKey: "defaultDurationMinutes") as? NSNumber)?.intValue ?? 0)
    }
    /// The island itself keeps the Mac awake while open or in use.
    var activityKeepsAwake: Bool { (defaults.object(forKey: "notchKeepAwakeActivity") as? Bool) ?? true }
    var preventDisplaySleep: Bool { (defaults.object(forKey: Self.preventDisplaySleepKey) as? Bool) ?? false }
    /// Out of scope: lid-closed mode needs root.
    var clamshellPreferred: Bool { (defaults.object(forKey: "clamshellPreferred") as? Bool) ?? false }
}
