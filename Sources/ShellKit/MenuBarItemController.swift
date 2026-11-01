import AppKit

/// Menu bar icon. A click opens the quick panel when the app lends one (`onTogglePanel`); a right click, or a
/// control-click, opens the menu with "Ouvrir Réglages", "Relancer" (when the app can) and "Quitter". Without a panel
/// the icon only has the menu, as before.
@MainActor
public final class MenuBarItemController: NSObject {
    /// The symbol drawn when the person has not chosen another one in "Barre des menus".
    static let defaultSymbol = "rectangle.topthird.inset.filled"
    /// Same key as the reference app's icon picker, which the ported Settings page writes.
    static let symbolKey = "menuBarIconSymbol"

    private let item: NSStatusItem
    private let defaults: UserDefaults
    private let onOpenSettings: @MainActor () -> Void
    private let onQuit: @MainActor () -> Void
    private let onRelaunch: (@MainActor () -> Void)?
    private let onTogglePanel: (@MainActor (NSStatusBarButton) -> Void)?
    private let menu: NSMenu
    private var observer: NSObjectProtocol?

    /// `onRelaunch` is nil outside an app bundle (a bare `swift run` cannot restart itself): no menu entry then.
    /// `onTogglePanel` is nil when no panel exists: the menu then opens on a plain click.
    public init(onOpenSettings: @escaping @MainActor () -> Void, onQuit: @escaping @MainActor () -> Void,
                onRelaunch: (@MainActor () -> Void)? = nil,
                onTogglePanel: (@MainActor (NSStatusBarButton) -> Void)? = nil,
                defaults: UserDefaults = .standard) {
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        self.onRelaunch = onRelaunch
        self.onTogglePanel = onTogglePanel
        self.defaults = defaults
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu = NSMenu()
        super.init()
        Self.fill(menu, target: self, canRelaunch: onRelaunch != nil)
        applyIcon()
        if onTogglePanel == nil {
            item.menu = menu
        } else {
            item.button?.target = self
            item.button?.action = #selector(clicked(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        // The picker writes the key from Settings: follow it without a relaunch.
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyIcon() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - Icon

    /// The symbol to draw: the stored name when this Mac has a symbol of that name, else the default one. Pure over
    /// `exists`, so the choice is testable without drawing.
    static func symbolName(stored: String?, exists: (String) -> Bool = { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }) -> String {
        let name = (stored ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && exists(name) ? name : defaultSymbol
    }

    private func applyIcon() {
        let name = Self.symbolName(stored: defaults.string(forKey: Self.symbolKey))
        guard item.button?.image == nil || shownSymbol != name else { return }
        shownSymbol = name
        item.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Mac Island")
    }

    private var shownSymbol: String?

    // MARK: - Click

    /// A right click or a control-click opens the menu; any other click is the panel's.
    static func opensMenu(type: NSEvent.EventType?, modifiers: NSEvent.ModifierFlags) -> Bool {
        type == .rightMouseUp || modifiers.contains(.control)
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if Self.opensMenu(type: event?.type, modifiers: event?.modifierFlags ?? []) {
            // The standard way to show a menu from a status item that has an action: attach it for one click.
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
        } else {
            onTogglePanel?(sender)
        }
    }

    /// Shows or hides the icon. Only the ported menu bar metrics ask (their "hide the app icon" option), and only
    /// while a metric item of their own is on screen.
    public func setIconVisible(_ visible: Bool) { item.isVisible = visible }

    // MARK: - Menu

    /// Entry titles in order; the menu and its tests share it.
    static func titles(canRelaunch: Bool) -> [String] {
        ["Ouvrir Réglages…"] + (canRelaunch ? ["Relancer Mac Island"] : []) + ["Quitter Mac Island"]
    }

    static func makeMenu(target: MenuBarItemController, canRelaunch: Bool) -> NSMenu {
        let menu = NSMenu()
        fill(menu, target: target, canRelaunch: canRelaunch)
        return menu
    }

    private static func fill(_ menu: NSMenu, target: MenuBarItemController, canRelaunch: Bool) {
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
    }

    @objc private func openSettings() { onOpenSettings() }
    @objc private func relaunch() { onRelaunch?() }
    @objc private func quit() { onQuit() }
}
