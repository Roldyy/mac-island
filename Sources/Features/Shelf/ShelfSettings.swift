import IslandKit
import Foundation

/// Read side of the preferences store. UserDefaults in the app, an in-memory fake in tests, so a
/// test never writes a plist into ~/Library/Preferences.
protocol KeyValueReading {
    func object(forKey key: String) -> Any?
}

extension UserDefaults: KeyValueReading {}

/// Preferences in the app's defaults suite for the part of the tab that is still ours (the Downloads pane).
/// The shelf's own options (`shelfEnabled`, shortcut, shake...) are the ported service's.
struct ShelfSettings {
    static let suiteName = "be.roldy.macisland"
    static let defaultLimit = 8
    static let maxLimit = 50

    let defaults: any KeyValueReading

    init(defaults: any KeyValueReading = AppDefaults.make() ?? .standard) {
        self.defaults = defaults
    }

    var shelfEnabled: Bool { (defaults.object(forKey: "shelfEnabled") as? Bool) ?? true }
    var downloadsEnabled: Bool { (defaults.object(forKey: "shelfDownloadsEnabled") as? Bool) ?? true }
    var downloadsLimit: Int {
        guard let n = (defaults.object(forKey: "shelfDownloadsLimit") as? NSNumber)?.intValue else {
            return Self.defaultLimit
        }
        return min(Self.maxLimit, max(1, n))
    }
}
