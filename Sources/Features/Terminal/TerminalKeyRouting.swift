import AppKit

/// What a key equivalent does inside the terminal. The island has no main menu, so none of these
/// shortcuts reaches the terminal through a menu item: the view routes them itself.
enum TerminalKeyAction: Equatable {
    case copy
    case paste
    case selectAll
    case clear
    case fontLarger
    case fontSmaller
    case fontReset
    /// Command-C with nothing selected: the terminal convention, the foreground program gets ^C.
    case interrupt
}

enum TerminalKeyRouting {
    /// Pure routing table. `key` is `charactersIgnoringModifiers`. Nil means "not ours": the event goes on
    /// (command-Q and the like must never be swallowed). Only a bare command modifier counts, apart from
    /// shift on the plus key, which is how most layouts type it.
    static func action(
        modifiers: NSEvent.ModifierFlags, key: String?, hasSelection: Bool
    ) -> TerminalKeyAction? {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        guard let key = key?.lowercased(), key.count == 1 else { return nil }
        let plusKey = key == "+" || key == "="
        guard flags == .command || (plusKey && flags == [.command, .shift]) else { return nil }
        switch key {
        case "c": return hasSelection ? .copy : .interrupt
        case "v": return .paste
        case "a": return .selectAll
        case "k": return .clear
        case "+", "=": return .fontLarger
        case "-": return .fontSmaller
        case "0": return .fontReset
        default: return nil
        }
    }
}
