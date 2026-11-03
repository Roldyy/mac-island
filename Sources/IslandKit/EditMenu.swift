import AppKit

/// A main menu with the standard Edit items, never drawn: the app is an accessory app (no menu bar), so this only
/// supplies the key equivalents a normal window (Settings) needs for Cmd+C / X / V / A / Z. The activation policy is
/// not touched. The island panel does not depend on it (`NotchPanel.performKeyEquivalent`).
@MainActor
public enum EditMenu {
    /// Adds the Edit menu unless the app's main menu already has a Paste item. Creates the main menu when there is none.
    public static func install(on app: NSApplication = .shared) {
        let main = app.mainMenu ?? NSMenu()
        guard !main.items.compactMap(\.submenu).contains(where: { $0.items.contains { $0.action == #selector(NSText.paste(_:)) } })
        else { return }
        if main.items.isEmpty { main.addItem(NSMenuItem()) }  // slot 0 is the application menu, left empty
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        edit.submenu = makeEditMenu()
        main.addItem(edit)
        if app.mainMenu == nil { app.mainMenu = main }
    }

    private static func makeEditMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        func add(_ title: String, _ action: Selector, _ key: String, _ flags: NSEvent.ModifierFlags = .command) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = flags
            menu.addItem(item)
        }
        add("Undo", NSSelectorFromString("undo:"), "z")
        add("Redo", NSSelectorFromString("redo:"), "z", [.command, .shift])
        menu.addItem(.separator())
        add("Cut", #selector(NSText.cut(_:)), "x")
        add("Copy", #selector(NSText.copy(_:)), "c")
        add("Paste", #selector(NSText.paste(_:)), "v")
        add("Select All", #selector(NSText.selectAll(_:)), "a")
        return menu
    }
}
