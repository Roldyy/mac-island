import Foundation

/// The two migrated keys (names found in the old app's defaults), read and written in the suite.
/// Cut/paste moves files, so it stays off until the user turned it on; an absent image key is on
/// (it only ever creates a new file). The old app's defaults for absent keys are UNKNOWN.
final class FinderSettings {
    static let suiteName = "be.roldy.macisland"
    static let cutPasteKey = "finderCutPasteEnabled"
    static let imageKey = "finderPasteImageAsFile"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = UserDefaults(suiteName: FinderSettings.suiteName) ?? .standard) {
        self.defaults = defaults
    }

    var cutPasteEnabled: Bool {
        get { (defaults.object(forKey: Self.cutPasteKey) as? Bool) ?? false }
        set { defaults.set(newValue, forKey: Self.cutPasteKey) }
    }
    var pasteImageAsFile: Bool {
        get { (defaults.object(forKey: Self.imageKey) as? Bool) ?? true }
        set { defaults.set(newValue, forKey: Self.imageKey) }
    }
}
