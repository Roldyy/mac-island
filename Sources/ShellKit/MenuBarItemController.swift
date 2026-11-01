import AppKit

/// Menu bar icon with "Ouvrir Réglages", "Relancer" (when the app can) and "Quitter".
@MainActor
public final class MenuBarItemController: NSObject {
    private let item: NSStatusItem
    private let onOpenSettings: @MainActor () -> Void
    private let onQuit: @MainActor () -> Void
    private let onRelaunch: (@MainActor () -> Void)?

    /// `onRelaunch` is nil outside an app bundle (a bare `swift run` cannot restart itself): no menu entry then.
    public init(onOpenSettings: @escaping @MainActor () -> Void, onQuit: @escaping @MainActor () -> Void,
                onRelaunch: (@MainActor () -> Void)? = nil) {
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        self.onRelaunch = onRelaunch
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled",
                                     accessibilityDescription: "Mac Island")
        item.menu = Self.makeMenu(target: self, canRelaunch: onRelaunch != nil)
    }

    /// Shows or hides the icon. Only the ported menu bar metrics ask (their "hide the app icon" option), and only
    /// while a metric item of their own is on screen.
    public func setIconVisible(_ visible: Bool) { item.isVisible = visible }

    /// Entry titles in order; the menu and its tests share it.
    static func titles(canRelaunch: Bool) -> [String] {
        ["Ouvrir Réglages…"] + (canRelaunch ? ["Relancer Mac Island"] : []) + ["Quitter Mac Island"]
    }

    static func makeMenu(target: MenuBarItemController, canRelaunch: Bool) -> NSMenu {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Ouvrir Réglages…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = target
        menu.addItem(settings)
        if canRelaunch {
            let relaunch = NSMenuItem(title: "Relancer Mac Island", action: #selector(relaunch), keyEquivalent: "r")
            relaunch.target = target
            menu.addItem(relaunch)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quitter Mac Island", action: #selector(quit), keyEquivalent: "q")
        quit.target = target
        menu.addItem(quit)
        return menu
    }

    @objc private func openSettings() { onOpenSettings() }
    @objc private func relaunch() { onRelaunch?() }
    @objc private func quit() { onQuit() }
}
