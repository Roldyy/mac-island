import Foundation

/// Reads and writes the Dock preference keys in the app's defaults suite.
/// Migrated from the old app (names kept, booleans stored as 1/0): dockClickMinimize, dockClickHide,
/// dockClickCycleWindows, dockPreviewEnabled. New (not migrated): dockPreviewDelayMilliseconds.
/// Absent means off: the island never starts intercepting Dock clicks on its own.
struct DockSettings {
    static let suiteName = "be.roldy.macisland"
    static let delayRange = 100...2000
    static let defaultDelayMilliseconds = 400

    let defaults: UserDefaults

    init(defaults: UserDefaults = UserDefaults(suiteName: DockSettings.suiteName) ?? .standard) {
        self.defaults = defaults
    }

    private func flag(_ key: String) -> Bool { (defaults.object(forKey: key) as? NSNumber)?.boolValue ?? false }

    var clickMinimize: Bool { get { flag("dockClickMinimize") } nonmutating set { defaults.set(newValue, forKey: "dockClickMinimize") } }
    var clickHide: Bool { get { flag("dockClickHide") } nonmutating set { defaults.set(newValue, forKey: "dockClickHide") } }
    var clickCycle: Bool { get { flag("dockClickCycleWindows") } nonmutating set { defaults.set(newValue, forKey: "dockClickCycleWindows") } }
    var previewEnabled: Bool { get { flag("dockPreviewEnabled") } nonmutating set { defaults.set(newValue, forKey: "dockPreviewEnabled") } }

    var clickOptions: DockClickOptions {
        DockClickOptions(minimize: clickMinimize, hide: clickHide, cycle: clickCycle)
    }

    var previewDelayMilliseconds: Int {
        get {
            let raw = (defaults.object(forKey: "dockPreviewDelayMilliseconds") as? NSNumber)?.intValue
                ?? Self.defaultDelayMilliseconds
            return min(max(raw, Self.delayRange.lowerBound), Self.delayRange.upperBound)
        }
        nonmutating set { defaults.set(newValue, forKey: "dockPreviewDelayMilliseconds") }
    }
    var previewDelay: TimeInterval { Double(previewDelayMilliseconds) / 1000 }
}
