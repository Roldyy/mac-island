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
    private let onOpenHistory: (@MainActor () -> Void)?
    private let onHidden: (@MainActor () -> Void)?
    private let menu: NSMenu
    private var observer: NSObjectProtocol?

    /// `onRelaunch` is nil outside an app bundle (a bare `swift run` cannot restart itself): no menu entry then.
    /// `onTogglePanel` is nil when no panel exists: the menu then opens on a plain click.
    public init(onOpenSettings: @escaping @MainActor () -> Void, onQuit: @escaping @MainActor () -> Void,
                onRelaunch: (@MainActor () -> Void)? = nil,
                onTogglePanel: (@MainActor (NSStatusBarButton) -> Void)? = nil,
                onOpenHistory: (@MainActor () -> Void)? = nil,
                onHidden: (@MainActor () -> Void)? = nil,
                defaults: UserDefaults = .standard) {
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        self.onRelaunch = onRelaunch
        self.onTogglePanel = onTogglePanel
        self.onOpenHistory = onOpenHistory
        self.onHidden = onHidden
        self.defaults = defaults
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu = NSMenu()
        super.init()
        Self.fill(menu, target: self, canRelaunch: onRelaunch != nil)
        applyIcon()
        applyVisibility()
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
            MainActor.assumeIsolated {
                self?.applyIcon()
                self?.applyVisibility()
            }
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
        } else if let event, Self.opensHistory(previewShown: preview != nil, clickX: clickX(of: event, in: sender),
                                               iconTrailingEdge: iconTrailingEdge(of: sender)),
                  let onOpenHistory {
            onOpenHistory()
        } else {
            onTogglePanel?(sender)
        }
    }

    // MARK: - Last copy preview

    /// The text shown next to the icon (nil: only the icon). Set by the Clipboard history's "Afficher la dernière
    /// copie dans la barre des menus"; the caller has already cut it to the length the person chose.
    public private(set) var preview: String?

    public func setPreview(_ text: String?) {
        let clean = text.flatMap { $0.isEmpty ? nil : $0 }
        guard clean != preview else { return }
        preview = clean
        applyPreview()
    }

    private func applyPreview() {
        guard let button = item.button else { return }
        if let preview {
            item.length = NSStatusItem.variableLength
            button.imagePosition = .imageLeading
            button.font = NSFont.menuBarFont(ofSize: 0)
            button.title = preview
            button.setAccessibilityLabel("Mac Island, dernière copie : \(preview)")
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
            item.length = NSStatusItem.squareLength
            button.setAccessibilityLabel("Mac Island")
        }
    }

    /// A click on the text (to the right of the icon) opens the history; a click on the icon keeps opening the quick
    /// panel. Pure, so the split is testable without a status bar.
    static func opensHistory(previewShown: Bool, clickX: CGFloat, iconTrailingEdge: CGFloat) -> Bool {
        previewShown && clickX > iconTrailingEdge
    }

    private func clickX(of event: NSEvent, in button: NSStatusBarButton) -> CGFloat {
        button.convert(event.locationInWindow, from: nil).x
    }

    private func iconTrailingEdge(of button: NSStatusBarButton) -> CGFloat {
        button.cell?.imageRect(forBounds: button.bounds).maxX ?? 0
    }

    /// The ported menu bar metrics' say (their "hide the app icon" option, only while a metric item shows). It never
    /// shows the icon on its own: the person's switch (`MenuBarIconPolicy`) must be on too.
    public func setIconVisible(_ visible: Bool) {
        metricsAllowIcon = visible
        applyVisibility()
    }

    private var metricsAllowIcon = true

    /// Whether the icon is on screen now.
    public var isIconVisible: Bool { item.isVisible }

    private func applyVisibility() {
        let visible = MenuBarIconPolicy.isVisible(userWantsIcon: MenuBarIconPolicy.isShown(defaults: defaults),
                                                  metricsAllowIcon: metricsAllowIcon)
        guard item.isVisible != visible else { return }
        item.isVisible = visible
        // A hidden item cannot anchor a panel: close whatever is open on it.
        if !visible { onHidden?() }
    }

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
