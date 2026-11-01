import AppKit
import Carbon.HIToolbox

/// Global "open the history" shortcut. Carbon `RegisterEventHotKey` needs no permission. It has its own id, apart
/// from the plain-paste key (`PlainPasteHotkeyService`, id 1): each handler answers only its own key and passes the
/// rest on, so the two never take each other's presses.
@MainActor
final class HistoryHotkeyService: PlainPasteHotkeyRegistering {
    private static weak var active: HistoryHotkeyService?
    nonisolated static let hotKeyID: UInt32 = 2

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private(set) var registered: HotkeyShortcut?
    var onTrigger: () -> Void = {}

    nonisolated static func isOurHotKey(signature: OSType, id: UInt32) -> Bool {
        signature == PlainPasteHotkeyService.signature && id == hotKeyID
    }

    /// Returns false when the shortcut is taken or invalid.
    @discardableResult
    func register(_ shortcut: HotkeyShortcut) -> Bool {
        unregister()
        Self.active = self
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, HistoryHotkeyService.isOurHotKey(signature: hotKeyID.signature, id: hotKeyID.id) else {
                return OSStatus(eventNotHandledErr)
            }
            Task { @MainActor in HistoryHotkeyService.active?.onTrigger() }
            return noErr
        }
        guard InstallEventHandler(GetApplicationEventTarget(), handler, 1, &spec, nil, &handlerRef) == noErr else {
            return false
        }
        let id = EventHotKeyID(signature: PlainPasteHotkeyService.signature, id: Self.hotKeyID)
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
}
