import Foundation

struct HotkeyModifiers: OptionSet, Hashable, Sendable {
    let rawValue: Int
    static let command = HotkeyModifiers(rawValue: 1)
    static let option = HotkeyModifiers(rawValue: 2)
    static let control = HotkeyModifiers(rawValue: 4)
    static let shift = HotkeyModifiers(rawValue: 8)
}

/// A global shortcut. Three spellings of the same combination are read:
/// - "option+command:9": modifiers, ":", the virtual KEY CODE (Vorssaint's stored form: 9 is V);
/// - "option+command:v" or "control+option+command:k": the same with a key name (Mac Island's own recorder);
/// - "option+command+v": no colon, the last "+" token is the key (name or code).
/// A bare number after the key separator is ALWAYS a key code, never the digit key of that name: the digit
/// keys are written as codes ("option+command:25" is the 9 key), so the two readings cannot collide.
struct HotkeyShortcut: Equatable, Sendable {
    var modifiers: HotkeyModifiers
    var key: String
    var keyCode: UInt32

    /// Matches the Settings page default ("option+command:9", that is the code of V): option-command-V.
    static let `default` = HotkeyShortcut(modifiers: [.option, .command], key: "v", keyCode: 9)

    /// Carbon `RegisterEventHotKey` flags: cmdKey 256, shiftKey 512, optionKey 2048, controlKey 4096.
    var carbonModifiers: UInt32 {
        var f: UInt32 = 0
        if modifiers.contains(.command) { f |= 256 }
        if modifiers.contains(.shift) { f |= 512 }
        if modifiers.contains(.option) { f |= 2048 }
        if modifiers.contains(.control) { f |= 4096 }
        return f
    }

    /// Canonical stored form, readable back by `parse`. Digit keys and keys without a name are written as codes.
    var stored: String {
        var names: [String] = []
        if modifiers.contains(.control) { names.append("control") }
        if modifiers.contains(.option) { names.append("option") }
        if modifiers.contains(.shift) { names.append("shift") }
        if modifiers.contains(.command) { names.append("command") }
        let keyText = (Self.keyCodes[key] != nil && Int(key) == nil) ? key : String(keyCode)
        return names.joined(separator: "+") + ":" + keyText
    }

    static func parse(_ raw: String) -> HotkeyShortcut? {
        let modifierText: String
        let keyText: String
        if let colon = raw.firstIndex(of: ":") {
            guard !raw[raw.index(after: colon)...].contains(":") else { return nil }
            modifierText = String(raw[..<colon])
            keyText = String(raw[raw.index(after: colon)...])
        } else {
            guard let plus = raw.lastIndex(of: "+"), plus != raw.index(before: raw.endIndex) else { return nil }
            modifierText = String(raw[..<plus])
            keyText = String(raw[raw.index(after: plus)...])
        }
        guard let (key, code) = resolveKey(keyText.trimmingCharacters(in: .whitespaces).lowercased()) else {
            return nil
        }
        var mods: HotkeyModifiers = []
        for token in modifierText.split(separator: "+") {
            switch token.trimmingCharacters(in: .whitespaces).lowercased() {
            case "command", "cmd": mods.insert(.command)
            case "option", "alt", "opt": mods.insert(.option)
            case "control", "ctrl": mods.insert(.control)
            case "shift": mods.insert(.shift)
            default: return nil
            }
        }
        guard !mods.isEmpty else { return nil }
        return HotkeyShortcut(modifiers: mods, key: key, keyCode: code)
    }

    /// A number is a virtual key code (0...127); anything else is a key name.
    private static func resolveKey(_ text: String) -> (String, UInt32)? {
        if let n = UInt32(text) {
            guard n <= 127 else { return nil }
            return (keyNames[n] ?? "key\(n)", n)
        }
        guard let code = keyCodes[text] else { return nil }
        return (text, code)
    }

    static let keyNames: [UInt32: String] = Dictionary(uniqueKeysWithValues: keyCodes.map { ($0.value, $0.key) })

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
