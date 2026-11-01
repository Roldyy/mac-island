/// What the model uses when no history hotkey is lent (tests that inject their own plain-paste fake): it records
/// the request and registers nothing, so a test never takes a real key of the machine.
@MainActor
final class UnregisteredHotkey: PlainPasteHotkeyRegistering {
    var onTrigger: () -> Void = {}
    private(set) var registered: HotkeyShortcut?
    private(set) var registerCalls: [HotkeyShortcut] = []
    var accept = true

    @discardableResult
    func register(_ shortcut: HotkeyShortcut) -> Bool {
        registerCalls.append(shortcut)
        guard accept else { registered = nil; return false }
        registered = shortcut
        return true
    }

    func unregister() { registered = nil }
    func press() { onTrigger() }
}
