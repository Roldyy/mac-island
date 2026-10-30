import AppKit
import Carbon.HIToolbox

@MainActor
protocol HotkeyRegistering: AnyObject {
    /// Returns the OSStatus of the registration (0 = ok).
    func register(_ spec: HotkeySpec, onTrigger: @escaping @MainActor () -> Void) -> Int32
    func unregister()
}

enum HotkeyStatus: Equatable {
    case off
    case active(String)
    case conflict
    case failed(Int32)

    static func from(osStatus: Int32, spec: HotkeySpec) -> HotkeyStatus {
        if osStatus == noErr { return .active(spec.display) }
        if osStatus == Int32(eventHotKeyExistsErr) { return .conflict }
        return .failed(osStatus)
    }

    /// Text for the tab.
    var message: String {
        switch self {
        case .off: return "d\u{00E9}sactiv\u{00E9}"
        case .active(let d): return "actif (\(d))"
        case .conflict: return "d\u{00E9}j\u{00E0} utilis\u{00E9}"
        case .failed(let code): return "erreur \(code)"
        }
    }
}

/// Global shortcut through Carbon `RegisterEventHotKey` (no permission needed). The Clipboard
/// feature installs its own handler on the same application target, so ours has a unique signature
/// ('MICB') and id, and answers `eventNotHandledErr` to every other hotkey so the next handler runs.
@MainActor
final class CommandBarHotkeyService: HotkeyRegistering {
    private static weak var active: CommandBarHotkeyService?
    nonisolated static let signature: OSType = 0x4D49_4342   // 'MICB'
    nonisolated static let hotKeyID: UInt32 = 0x4342

    nonisolated static func isOurHotKey(signature: OSType, id: UInt32) -> Bool {
        signature == Self.signature && id == hotKeyID
    }

    /// What the Carbon handler returns: handled only for our own id.
    nonisolated static func handlerResult(signature: OSType, id: UInt32) -> OSStatus {
        isOurHotKey(signature: signature, id: id) ? noErr : OSStatus(eventNotHandledErr)
    }

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var onTrigger: (@MainActor () -> Void)?

    func register(_ spec: HotkeySpec, onTrigger: @escaping @MainActor () -> Void) -> Int32 {
        unregister()
        Self.active = self
        self.onTrigger = onTrigger

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return OSStatus(eventNotHandledErr) }
            let result = CommandBarHotkeyService.handlerResult(signature: hotKeyID.signature, id: hotKeyID.id)
            if result == noErr {
                Task { @MainActor in CommandBarHotkeyService.active?.onTrigger?() }
            }
            return result
        }
        let installed = InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &handlerRef)
        guard installed == noErr else { unregister(); return installed }

        let id = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        let status = RegisterEventHotKey(spec.keyCode, spec.carbonModifiers, id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr { unregister() }
        return status
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let h = handlerRef { RemoveEventHandler(h) }
        hotKeyRef = nil
        handlerRef = nil
        onTrigger = nil
    }
}
