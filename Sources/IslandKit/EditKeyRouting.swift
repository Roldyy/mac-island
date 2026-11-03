import AppKit

/// The standard editing shortcuts that arrive as key equivalents. Cmd+arrows, Option+arrows and Cmd+Backspace are
/// not here: they are key bindings AppKit resolves in `keyDown`, which the panel already delivers.
public enum EditKeyAction: Equatable, Sendable {
    case copy, cut, paste, selectAll, undo, redo
}

/// Why this exists: the island is a non-activating panel of an accessory app, which has no Edit menu, so nothing
/// turned Cmd+C / X / V / A / Z into `copy:` / `cut:` / `paste:` / `selectAll:` / `undo:` for the text view that
/// holds the keyboard. `NotchPanel.performKeyEquivalent` routes them here, once, for every text input in the island.
public enum EditKeyRouting {
    /// Pure: which action a key press stands for. Command alone (Shift too for redo); Option+Command+V and the
    /// other chords belong to global hotkeys and to the terminal and are never taken.
    public static func action(modifiers: NSEvent.ModifierFlags, key: String?) -> EditKeyAction? {
        let flags = modifiers.intersection([.command, .shift, .option, .control])
        guard let key = key?.lowercased() else { return nil }
        if flags == .command {
            switch key {
            case "c": return .copy
            case "x": return .cut
            case "v": return .paste
            case "a": return .selectAll
            case "z": return .undo
            default: return nil
            }
        }
        if flags == [.command, .shift], key == "z" { return .redo }
        return nil
    }

    /// Sends the key press to the window's first responder when that is a text input (an `NSText`: a text view or
    /// a field editor). The terminal and any other view are left alone. Nothing is taken while an input method
    /// is composing. Returns whether the key press was consumed.
    @MainActor
    public static func handle(_ event: NSEvent, in window: NSWindow) -> Bool {
        guard event.type == .keyDown,
              let action = action(modifiers: event.modifierFlags, key: event.charactersIgnoringModifiers),
              let responder = window.firstResponder as? NSText,
              !((responder as? NSTextInputClient)?.hasMarkedText() ?? false)
        else { return false }
        switch action {
        case .copy: return responder.tryToPerform(#selector(NSText.copy(_:)), with: window)
        case .cut: return responder.tryToPerform(#selector(NSText.cut(_:)), with: window)
        case .paste: return responder.tryToPerform(#selector(NSText.paste(_:)), with: window)
        case .selectAll: return responder.tryToPerform(#selector(NSText.selectAll(_:)), with: window)
        case .undo:
            guard let manager = responder.undoManager, manager.canUndo else { return true }
            manager.undo()
            return true
        case .redo:
            guard let manager = responder.undoManager, manager.canRedo else { return true }
            manager.redo()
            return true
        }
    }
}
