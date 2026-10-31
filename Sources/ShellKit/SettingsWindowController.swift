import AppKit
import IslandKit
import SwiftUI

/// Hosts the Settings view in a regular window. One instance; `show()` reuses it.
@MainActor
public final class SettingsWindowController {
    private var window: NSWindow?
    private let registry: FeatureRegistry
    private let tabs: [IslandTab]
    private let openPermission: @MainActor (FeaturePermission) -> Void

    public init(registry: FeatureRegistry, tabs: [IslandTab],
                openPermission: @escaping @MainActor (FeaturePermission) -> Void) {
        self.registry = registry
        self.tabs = tabs
        self.openPermission = openPermission
    }

    public func show() {
        if window == nil {
            let outside = Set(ShellLayout.tabsOutsideGroups(tabs.map(\.id)))
            let sheetTabs = Dictionary(uniqueKeysWithValues: tabs.filter { outside.contains($0.id) }.map { ($0.id, $0) })
            let view = SettingsView(registry: registry, sheetTabs: sheetTabs, openPermission: openPermission)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Réglages de Mac Island"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 620, height: 600))
            window.center()
            self.window = window
        }
        registry.refreshCapabilities()  // the user may have just granted something in System Settings
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
