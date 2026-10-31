import Foundation

/// Test-only helpers. Defaults suites live in the temp directory so no test leaves a plist in
/// ~/Library/Preferences.
public enum TestDefaults {
    public static func make(_ name: String = UUID().uuidString) -> (defaults: UserDefaults, cleanup: () -> Void) {
        let path = NSTemporaryDirectory() + "mis-test-\(name)"
        let defaults = UserDefaults(suiteName: path)!
        return (defaults, { defaults.removePersistentDomain(forName: path); try? FileManager.default.removeItem(atPath: path + ".plist") })
    }
}
