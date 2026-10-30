import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum PlainPasteOutcome: Equatable {
    case pasted
    case copiedOnly          // plain text is on the pasteboard, Cmd+V not sent (no Accessibility)
    case nothingToPaste
}

/// Global "paste as plain text" shortcut. Carbon `RegisterEventHotKey` needs no permission;
/// the synthetic Cmd+V needs Accessibility. We only ever read `AXIsProcessTrusted()`, never prompt.
@MainActor
final class PlainPasteHotkeyService {
    private static weak var active: PlainPasteHotkeyService?
    private static let signature: OSType = 0x4D49_434C   // 'MICL'

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private(set) var registered: HotkeyShortcut?
    var onTrigger: () -> Void = {}

    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Returns false when the shortcut is taken or invalid.
    @discardableResult
    func register(_ shortcut: HotkeyShortcut) -> Bool {
        unregister()
        Self.active = self

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, _, _ in
            Task { @MainActor in PlainPasteHotkeyService.active?.onTrigger() }
            return noErr
        }
        guard InstallEventHandler(GetApplicationEventTarget(), handler, 1, &spec, nil, &handlerRef) == noErr else {
            return false
        }
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else { unregister(); return false }
        registered = shortcut
        return true
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let h = handlerRef { RemoveEventHandler(h) }
        hotKeyRef = nil
        handlerRef = nil
        registered = nil
    }

    /// Replace the pasteboard with its plain, normalised text, then send Cmd+V if allowed.
    static func performPlainPaste(pasteboard: NSPasteboard = .general,
                                  afterWrite: () -> Void = {}) -> PlainPasteOutcome {
        guard let raw = pasteboard.string(forType: .string) else { return .nothingToPaste }
        pasteboard.clearContents()
        pasteboard.setString(PlainPaste.normalize(raw), forType: .string)
        afterWrite()
        guard accessibilityTrusted else { return .copiedOnly }
        // Let the user release the shortcut's modifiers first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { postCommandV() }
        return .pasted
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let v = CGKeyCode(kVK_ANSI_V)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
