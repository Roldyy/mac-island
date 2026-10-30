import Foundation

/// A throwaway defaults suite with a uuid-based name. The suite name is an absolute path in the temp
/// directory, so the plist is written there and never in ~/Library/Preferences. The domain is removed
/// and the file deleted when the handle is released. Hold it in a class-based suite (its deinit runs
/// after the test) or keep it alive with `withExtendedLifetime`.
final class TempDefaults {
    let suite: String
    let defaults: UserDefaults

    init(prefix: String = "dock-test") {
        suite = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)").path
        defaults = UserDefaults(suiteName: suite)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suite)
        defaults.synchronize()
        try? FileManager.default.removeItem(atPath: suite + ".plist")
    }
}
