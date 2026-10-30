import Foundation

/// Reads the migrated preference keys (old names kept) from the app's defaults suite.
struct ClipboardSettings {
    static let suiteName = "be.roldy.macisland"
    static let defaultLimit = 50
    static let maxLimit = 500
    /// New key (not migrated): bundle ids whose copies are never recorded. Default empty.
    static let excludedKey = "clipboardExcludedBundleIDs"

    let defaults: UserDefaults

    init(defaults: UserDefaults = UserDefaults(suiteName: ClipboardSettings.suiteName) ?? .standard) {
        self.defaults = defaults
    }

    private func number(_ key: String) -> Double? { (defaults.object(forKey: key) as? NSNumber)?.doubleValue }

    var historyLimit: Int {
        guard let n = number("clipboardHistoryLimit") else { return Self.defaultLimit }
        return min(Self.maxLimit, max(1, Int(n)))
    }
    /// The old app kept a separate on/off boolean next to the delay; absent means off, so a
    /// migrated delay alone never wipes the pasteboard.
    var autoClearEnabled: Bool { (defaults.object(forKey: "clipboardAutoClearOnDelay") as? Bool) ?? false }
    var autoClearDelay: TimeInterval {
        guard autoClearEnabled else { return 0 }
        return max(0, number("clipboardAutoClearDelaySeconds") ?? 0)
    }
    var historyEnabled: Bool { (defaults.object(forKey: "clipboardHistoryEnabled") as? Bool) ?? true }
    var pastePlainEnabled: Bool { (defaults.object(forKey: "pastePlainEnabled") as? Bool) ?? true }
    var pastePlainShortcut: HotkeyShortcut {
        (defaults.string(forKey: "pastePlainShortcut")).flatMap(HotkeyShortcut.parse) ?? .default
    }
    var excludedBundleIDs: Set<String> { Set(defaults.stringArray(forKey: Self.excludedKey) ?? []) }
}
