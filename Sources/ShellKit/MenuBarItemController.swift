import AppKit

/// Menu bar icon with "Ouvrir Réglages" and "Quitter".
@MainActor
public final class MenuBarItemController: NSObject {
    private let item: NSStatusItem
    private let onOpenSettings: @MainActor () -> Void
    private let onQuit: @MainActor () -> Void

    public init(onOpenSettings: @escaping @MainActor () -> Void, onQuit: @escaping @MainActor () -> Void) {
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled",
                                     accessibilityDescription: "Mac Island")
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Ouvrir Réglages…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        let quit = NSMenuItem(title: "Quitter Mac Island", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(quit)
        item.menu = menu
    }

    @objc private func openSettings() { onOpenSettings() }
    @objc private func quit() { onQuit() }
}
