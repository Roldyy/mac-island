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
    private let defaults: UserDefaults
    private var router: SettingsRouter?

    public init(registry: FeatureRegistry, tabs: [IslandTab],
                openPermission: @escaping @MainActor (FeaturePermission) -> Void,
                relaunch: (@MainActor () -> Void)? = nil,
                defaults: UserDefaults = AppDefaults.make() ?? .standard) {
        self.defaults = defaults
        self.relaunch = relaunch
        self.registry = registry
        self.tabs = tabs
        self.openPermission = openPermission
        AppearancePreference.load(from: defaults).apply()  // the whole app follows the choice from launch
    }

    public func show() {
        if window == nil {
            let outside = Set(ShellLayout.tabsOutsideGroups(tabs.map(\.id)))
            let sheetTabs = Dictionary(uniqueKeysWithValues: tabs.filter { outside.contains($0.id) }.map { ($0.id, $0) })
            let router = SettingsRouter(defaults: defaults)
            self.router = router
            // After an update, "Nouveautés" opens once ("Afficher les nouveautés après mise à jour").
            if WhatsNewAfterUpdate.consume(defaults: defaults, current: AboutVersion.current()) { router.open("whatsnew") }
            let env = SettingsEnvironment(
                registry: registry, defaults: defaults, sheetTabs: sheetTabs, openPermission: openPermission,
                relaunch: relaunch, login: LoginItemModel(defaults: defaults),
                backup: SettingsBackup(defaults: defaults, domain: AppDefaults.identifier),
                navigate: { [weak router] id in router?.open(id) })
            AppearancePreference.load(from: defaults).apply()
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsRootView(env: env, router: router)))
            window.title = "Réglages de Mac Island"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 772, height: 528)
            window.setContentSize(NSSize(width: 900, height: 640))
            window.setFrameAutosaveName("MacIslandSettings")
            if !window.setFrameUsingName("MacIslandSettings") { window.center() }
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
        let checkerDefaults = defaults
        Task { await UpdateChecker.shared.checkIfStale(defaults: checkerDefaults) }  // "automatiquement": a day apart at most
        registry.refreshCapabilities()  // the user may have just granted something in System Settings
        registry.permissionMonitor?.recheck()
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
