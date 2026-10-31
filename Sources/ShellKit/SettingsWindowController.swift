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
    private let relaunch: (@MainActor () -> Void)?
    private var poller: Timer?
    private var observers: [NSObjectProtocol] = []

    public init(registry: FeatureRegistry, tabs: [IslandTab],
                openPermission: @escaping @MainActor (FeaturePermission) -> Void,
                relaunch: (@MainActor () -> Void)? = nil) {
        self.relaunch = relaunch
        self.registry = registry
        self.tabs = tabs
        self.openPermission = openPermission
    }

    public func show() {
        if window == nil {
            let outside = Set(ShellLayout.tabsOutsideGroups(tabs.map(\.id)))
            let sheetTabs = Dictionary(uniqueKeysWithValues: tabs.filter { outside.contains($0.id) }.map { ($0.id, $0) })
            let view = SettingsView(registry: registry, sheetTabs: sheetTabs, openPermission: openPermission,
                                relaunch: relaunch)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Réglages de Mac Island"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 620, height: 600))
            window.center()
            self.window = window
            // Mac Island is an accessory app and gets no activation signal when the user comes back from
            // System Settings, so poll while the window is on screen and refresh on every key/close event.
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.startPolling() }
                },
                center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.stopPolling() }
                },
            ]
        }
        startPolling()
        registry.refreshCapabilities()  // the user may have just granted something in System Settings
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func startPolling() {
        registry.refreshCapabilities()
        guard poller == nil else { return }
        poller = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.registry.refreshCapabilities() }
        }
    }

    private func stopPolling() {
        poller?.invalidate()
        poller = nil
    }
}
