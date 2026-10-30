import Foundation

struct HotkeyModifiers: OptionSet, Hashable, Sendable {
    let rawValue: Int
    static let command = HotkeyModifiers(rawValue: 1)
    static let option = HotkeyModifiers(rawValue: 2)
    static let control = HotkeyModifiers(rawValue: 4)
    static let shift = HotkeyModifiers(rawValue: 8)
}

/// A global shortcut as stored by the old app: "option+command:9" (modifiers, ":", key).
struct HotkeyShortcut: Equatable, Sendable {
    var modifiers: HotkeyModifiers
    var key: String
    var keyCode: UInt32

    static let `default` = HotkeyShortcut(modifiers: [.option, .command], key: "9", keyCode: 25)

    /// Carbon `RegisterEventHotKey` flags: cmdKey 256, shiftKey 512, optionKey 2048, controlKey 4096.
    var carbonModifiers: UInt32 {
        var f: UInt32 = 0
        if modifiers.contains(.command) { f |= 256 }
        if modifiers.contains(.shift) { f |= 512 }
        if modifiers.contains(.option) { f |= 2048 }
        if modifiers.contains(.control) { f |= 4096 }
        return f
    }

    /// Canonical stored form, readable back by `parse`.
    var stored: String {
        var names: [String] = []
        if modifiers.contains(.control) { names.append("control") }
        if modifiers.contains(.option) { names.append("option") }
        if modifiers.contains(.shift) { names.append("shift") }
        if modifiers.contains(.command) { names.append("command") }
        return names.joined(separator: "+") + ":" + key
    }

    static func parse(_ raw: String) -> HotkeyShortcut? {
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let keyName = parts[1].trimmingCharacters(in: .whitespaces).lowercased()
        guard let code = keyCodes[keyName] else { return nil }

        var mods: HotkeyModifiers = []
        for token in parts[0].split(separator: "+") {
            switch token.trimmingCharacters(in: .whitespaces).lowercased() {
            case "command", "cmd": mods.insert(.command)
            case "option", "alt", "opt": mods.insert(.option)
            case "control", "ctrl": mods.insert(.control)
            case "shift": mods.insert(.shift)
            default: return nil
            }
        }
        guard !mods.isEmpty else { return nil }
        return HotkeyShortcut(modifiers: mods, key: keyName, keyCode: code)
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
}
