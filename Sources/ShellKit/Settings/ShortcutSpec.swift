import AppKit
import Foundation

/// A global shortcut in the stored style "option+command:9" (modifiers, ":", key).
/// The same text the Clipboard and Command bar features read, so a value written here works for them.
public struct ShortcutSpec: Equatable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1)
        public static let option = Modifiers(rawValue: 2)
        public static let control = Modifiers(rawValue: 4)
        public static let shift = Modifiers(rawValue: 8)
    }

    public var modifiers: Modifiers
    public var key: String
    public var keyCode: UInt32

    public init(modifiers: Modifiers, key: String, keyCode: UInt32) {
        self.modifiers = modifiers
        self.key = key
        self.keyCode = keyCode
    }

    /// ⌃⌥⌘K, the default of "Garder éveillé".
    public static let keepAwakeDefault = ShortcutSpec(modifiers: [.control, .option, .command], key: "k", keyCode: 40)

    public var stored: String {
        var names: [String] = []
        if modifiers.contains(.control) { names.append("control") }
        if modifiers.contains(.option) { names.append("option") }
        if modifiers.contains(.shift) { names.append("shift") }
        if modifiers.contains(.command) { names.append("command") }
        return names.joined(separator: "+") + ":" + key
    }

    /// "⌃⌥⌘K".
    public var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "\u{2303}" }
        if modifiers.contains(.option) { s += "\u{2325}" }
        if modifiers.contains(.shift) { s += "\u{21E7}" }
        if modifiers.contains(.command) { s += "\u{2318}" }
        let named = ["space": "Espace", "return": "Retour", "tab": "Tab", "delete": "Suppr.", "escape": "Échap"]
        return s + (named[key] ?? key.uppercased())
    }

    /// Carbon flags for `RegisterEventHotKey`: cmdKey 256, shiftKey 512, optionKey 2048, controlKey 4096.
    public var carbonModifiers: UInt32 {
        var f: UInt32 = 0
        if modifiers.contains(.command) { f |= 256 }
        if modifiers.contains(.shift) { f |= 512 }
        if modifiers.contains(.option) { f |= 2048 }
        if modifiers.contains(.control) { f |= 4096 }
        return f
    }

    public static func parse(_ raw: String) -> ShortcutSpec? {
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let name = parts[1].trimmingCharacters(in: .whitespaces).lowercased()
        guard let code = keyCodes[name] else { return nil }
        var mods: Modifiers = []
        for token in parts[0].split(separator: "+") {
            switch token.trimmingCharacters(in: .whitespaces).lowercased() {
            case "command", "cmd": mods.insert(.command)
            case "option", "alt", "opt": mods.insert(.option)
            case "control", "ctrl": mods.insert(.control)
            case "shift": mods.insert(.shift)
            default: return nil
            }
        }
        // Shift alone only types a capital letter: not a usable global shortcut.
        guard !mods.isDisjoint(with: [.command, .option, .control]) else { return nil }
        return ShortcutSpec(modifiers: mods, key: name, keyCode: code)
    }

    /// Turns a key press into a shortcut, or nil when it cannot be one (no modifier, unknown key).
    public static func from(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> ShortcutSpec? {
        guard let name = keyNames[UInt32(keyCode)] else { return nil }
        var mods: Modifiers = []
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.shift) { mods.insert(.shift) }
        guard !mods.isDisjoint(with: [.command, .option, .control]) else { return nil }
        return ShortcutSpec(modifiers: mods, key: name, keyCode: UInt32(keyCode))
    }

    /// ANSI virtual key codes (kVK_ANSI_*), plus a few named keys.
    static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
        "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31,
        "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
        ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50,
        "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53,
    ]

    static let keyNames: [UInt32: String] = Dictionary(uniqueKeysWithValues: keyCodes.map { ($0.value, $0.key) })
}
