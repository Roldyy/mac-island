import IslandKit
import Foundation

/// Read side of the preferences store. UserDefaults in the app, an in-memory fake in tests, so a
/// test never writes a plist into ~/Library/Preferences.
protocol KeyValueReading {
    func object(forKey key: String) -> Any?
}

extension UserDefaults: KeyValueReading {}

/// The two preferences this module still reads itself (everything else about Keep Awake is read by the ported
/// manager): the island's own hold and the default duration the Éveil tab opens on. Migrated keys, old names kept;
/// an absent key means the default below.
struct KeepAwakeSettings {
    let defaults: any KeyValueReading

    init(defaults: any KeyValueReading = AppDefaults.make() ?? .standard) {
        self.defaults = defaults
    }

    /// 0 = no limit.
    var defaultDurationMinutes: Int {
        max(0, (defaults.object(forKey: "defaultDurationMinutes") as? NSNumber)?.intValue ?? 0)
    }
    /// The island itself keeps the Mac awake while open or in use.
    var activityKeepsAwake: Bool { (defaults.object(forKey: "notchKeepAwakeActivity") as? Bool) ?? true }
}
