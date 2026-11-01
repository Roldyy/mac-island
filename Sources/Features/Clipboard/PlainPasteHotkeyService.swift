import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum PlainPasteOutcome: Equatable {
    case pasted
    case copiedOnly          // plain text is on the pasteboard, Cmd+V not sent (no Accessibility)
    case nothingToPaste
}

/// What the model needs from a global hotkey: tests substitute a fake that records registrations.
@MainActor
protocol PlainPasteHotkeyRegistering: AnyObject {
    var onTrigger: () -> Void { get set }
    var registered: HotkeyShortcut? { get }
    @discardableResult func register(_ shortcut: HotkeyShortcut) -> Bool
    func unregister()
}

/// Global "paste as plain text" shortcut. Carbon `RegisterEventHotKey` needs no permission;
/// the synthetic Cmd+V needs Accessibility. We only ever read `AXIsProcessTrusted()`, never prompt.
@MainActor
final class PlainPasteHotkeyService: PlainPasteHotkeyRegistering {
    private static weak var active: PlainPasteHotkeyService?
    nonisolated static let signature: OSType = 0x4D49_434C   // 'MICL'
    nonisolated static let hotKeyID: UInt32 = 1
    nonisolated static func isOurHotKey(_ id: EventHotKeyID) -> Bool {
        isOurHotKey(signature: id.signature, id: id.id)
    }
    nonisolated static func isOurHotKey(signature: OSType, id: UInt32) -> Bool {
        signature == Self.signature && id == hotKeyID
    }

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private(set) var registered: HotkeyShortcut?
    var onTrigger: () -> Void = {}

    nonisolated static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Returns false when the shortcut is taken or invalid.
    @discardableResult
    func register(_ shortcut: HotkeyShortcut) -> Bool {
        unregister()
        Self.active = self

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, event, _ in
            // Not ours (another Carbon hotkey in the process): let the next handler have it.
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, PlainPasteHotkeyService.isOurHotKey(hotKeyID) else {
                return OSStatus(eventNotHandledErr)
            }
            Task { @MainActor in PlainPasteHotkeyService.active?.onTrigger() }
            return noErr
        }
        guard InstallEventHandler(GetApplicationEventTarget(), handler, 1, &spec, nil, &handlerRef) == noErr else {
            return false
        }
        let id = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
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
    /// The plain text is on the pasteboard BEFORE `sendPaste` runs. `sendPaste` waits for the shortcut's
    /// modifiers to be released (see `PasteKeySequencer`), so it runs on a task, not inline.
    static func performPlainPaste(pasteboard: NSPasteboard = .general,
                                  accessibilityTrusted: () -> Bool = { PlainPasteHotkeyService.accessibilityTrusted },
                                  postAccess: () -> Bool = { CGPreflightPostEventAccess() },
                                  sendPaste: @escaping @MainActor () async -> PasteSendResult = { await PasteKeySequencer.live().run() },
                                  didSend: @escaping @MainActor (PasteSendResult) -> Void = { _ in },
                                  afterWrite: () -> Void = {}) -> PlainPasteOutcome {
        guard let raw = pasteboard.string(forType: .string) else {
            PasteLog.logger.notice("nothing to paste: no string flavour")
            return .nothingToPaste
        }
        // Rewriting drops every flavour, including the password-manager markers: carry them over
        // (empty data is how the convention is written) so the item stays unrecordable.
        let markers = blockedMarkers(on: pasteboard)
        let before = pasteboard.types?.map(\.rawValue) ?? []
        pasteboard.clearContents()
        pasteboard.setString(PlainPaste.normalize(raw), forType: .string)
        for m in markers { pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType(m)) }
        let after = pasteboard.types?.map(\.rawValue) ?? []
        PasteLog.logger.notice("pasteboard converted: types \(before.joined(separator: ","), privacy: .public) -> \(after.joined(separator: ","), privacy: .public)")
        afterWrite()
        guard accessibilityTrusted() else {
            PasteLog.logger.notice("not posted: Accessibility not granted (AXIsProcessTrusted false)")
            return .copiedOnly
        }
        guard postAccess() else {
            PasteLog.logger.notice("not posted: no post-event access (CGPreflightPostEventAccess false)")
            return .copiedOnly
        }
        Task { @MainActor in
            let result = await sendPaste()
            didSend(result)
        }
        return .pasted
    }

    nonisolated static func blockedMarkers(on pasteboard: NSPasteboard) -> [String] {
        var seen = Set<String>()
        var all = pasteboard.types?.map(\.rawValue) ?? []
        for item in pasteboard.pasteboardItems ?? [] { all.append(contentsOf: item.types.map(\.rawValue)) }
        return all.filter { PasteboardFilter.blockedTypes.contains($0) && seen.insert($0).inserted }
    }
}
