/// Virtual key codes (ANSI layout, the same on every Mac keyboard for these four keys).
enum KeyCode {
    static let c = 8
    static let x = 7
    static let v = 9
    static let esc = 53
}

/// A key press reduced to what the decision needs. Caps lock, fn and numpad flags are ignored
/// on purpose: only command, shift, option and control change the meaning of a shortcut.
struct KeyChord: Equatable, Sendable {
    var keyCode: Int
    var command: Bool
    var shift: Bool
    var option: Bool
    var control: Bool
    var isRepeat: Bool

    var commandOnly: Bool { command && !shift && !option && !control }
    var noModifiers: Bool { !command && !shift && !option && !control }
}
