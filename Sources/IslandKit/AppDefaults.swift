import Foundation

/// The one way features reach the app's preferences.
///
/// Settings live in the domain `be.roldy.macisland`. Inside the bundled app that domain is the
/// standard one, and a named suite equal to the app's own bundle id is invalid, so the standard
/// defaults are used there. A bare `swift run` binary has no bundle id and uses the named suite,
/// which points at the same plist: both paths read and write the same file.
public enum AppDefaults {
    public static let identifier = "be.roldy.macisland"

    public static func make(bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> UserDefaults? {
        if bundleIdentifier == identifier { return .standard }
        return UserDefaults(suiteName: identifier)
    }
}
