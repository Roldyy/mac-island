import Foundation

/// Whether Mac Island's own menu bar icon is on screen. Hidden by default ("juste les standards de macOS"): the
/// island already carries Settings, Relaunch and Quit. One switch in Settings, "Barre des menus", shows it again.
///
/// Hand-written key: the upstream `notchHidesMenuBarIcon` is dead in Mac Island and is not reused.
public enum MenuBarIconPolicy {
    public static let key = "menuBarIconShown"

    /// The person's choice. An absent key is `false`: hidden.
    public static func isShown(defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: key)
    }

    /// The icon is visible only when the person wants it AND the menu bar metrics do not hide it (their option
    /// "hide the app icon while a metric shows"). Pure, so the combination is testable without a status bar.
    public static func isVisible(userWantsIcon: Bool, metricsAllowIcon: Bool) -> Bool {
        userWantsIcon && metricsAllowIcon
    }
}
