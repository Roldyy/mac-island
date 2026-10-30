import IslandKit
import Foundation

/// Preferences in the app's defaults suite. The old app's only `commandBar*` key
/// (`commandBarQueryHabitKey`) is deliberately not migrated and never read; every key below is new.
struct CommandBarSettings {
    static let suiteName = "be.roldy.macisland"
    static let enabledKey = "commandBarEnabled"
    static let hotkeyKey = "commandBarHotkey"
    static let habitsKey = "commandBarHabitsEnabled"
    static func sourceKey(_ id: String) -> String { "commandBarSource" + id.prefix(1).uppercased() + id.dropFirst() }
    static let sourceIDs = ["apps", "files", "calculator", "web", "commands"]

    let defaults: UserDefaults

    init(defaults: UserDefaults = AppDefaults.make() ?? .standard) {
        self.defaults = defaults
    }

    var enabled: Bool {
        get { (defaults.object(forKey: Self.enabledKey) as? Bool) ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    var habitsEnabled: Bool {
        get { (defaults.object(forKey: Self.habitsKey) as? Bool) ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.habitsKey) }
    }

    var hotkeyRaw: String {
        get { defaults.string(forKey: Self.hotkeyKey) ?? HotkeySpec.default.stored }
        nonmutating set { defaults.set(newValue, forKey: Self.hotkeyKey) }
    }

    var hotkey: HotkeySpec { HotkeySpec.parse(hotkeyRaw) ?? .default }

    func sourceEnabled(_ id: String) -> Bool {
        (defaults.object(forKey: Self.sourceKey(id)) as? Bool) ?? true
    }

    func setSource(_ id: String, enabled: Bool) {
        defaults.set(enabled, forKey: Self.sourceKey(id))
    }
}
