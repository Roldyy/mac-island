import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import ClipboardFeature

/// The real Carbon services, with a polite handler installed AFTER them (what every other feature in the app does):
/// a press reaches the owner exactly once, and a foreign press never fires them.
@MainActor
@Suite(.serialized) struct HotkeyDeliveryTests {
    final class Later {
        var seen = 0
        var ref: EventHandlerRef?
    }

    static func installPoliteHandler(_ later: Later) {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            if let event {
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            }
            guard id.signature == 0x5655_5348 else { return OSStatus(eventNotHandledErr) }
            Unmanaged<Later>.fromOpaque(userData).takeUnretainedValue().seen += 1
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(later).toOpaque(), &later.ref)
    }

    static func press(signature: OSType, id: UInt32) {
        var event: EventRef?
        CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, 0, &event)
        var hotKeyID = EventHotKeyID(signature: signature, id: id)
        SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                          MemoryLayout<EventHotKeyID>.size, &hotKeyID)
        SendEventToEventTarget(event, GetApplicationEventTarget())
        if let event { ReleaseEvent(event) }
    }

    @Test func plainPastePressFiresOnTriggerOnceAmongOtherHandlers() async throws {
        let plain = PlainPasteHotkeyService()
        let history = HistoryHotkeyService()
        var plainFired = 0, historyFired = 0
        plain.onTrigger = { plainFired += 1 }
        history.onTrigger = { historyFired += 1 }
        // Combinations nobody uses, so the test never takes a real key.
        #expect(plain.register(HotkeyShortcut(modifiers: [.control, .option, .shift, .command], key: "7", keyCode: 26)))
        #expect(history.register(HotkeyShortcut(modifiers: [.control, .option, .shift, .command], key: "8", keyCode: 28)))
        let later = Later()
        Self.installPoliteHandler(later)
        defer {
            if let ref = later.ref { RemoveEventHandler(ref) }
            plain.unregister(); history.unregister()
        }

        Self.press(signature: PlainPasteHotkeyService.signature, id: PlainPasteHotkeyService.hotKeyID)
        try await Task.sleep(for: .milliseconds(150))
        #expect(plainFired == 1 && historyFired == 0 && later.seen == 0)

        Self.press(signature: PlainPasteHotkeyService.signature, id: HistoryHotkeyService.hotKeyID)
        try await Task.sleep(for: .milliseconds(150))
        #expect(plainFired == 1 && historyFired == 1)

        Self.press(signature: 0x5655_5348, id: 2)   // another feature's key
        try await Task.sleep(for: .milliseconds(150))
        #expect(plainFired == 1 && historyFired == 1 && later.seen == 1)
    }

    @Test func registeringTheSameCombinationTwiceInOneProcessIsReportedAsRefused() {
        let a = PlainPasteHotkeyService()
        let b = HistoryHotkeyService()
        let combo = HotkeyShortcut(modifiers: [.control, .option, .shift, .command], key: "6", keyCode: 22)
        defer { a.unregister(); b.unregister() }
        #expect(a.register(combo))
        #expect(!b.register(combo), "RegisterEventHotKey answers eventHotKeyExistsErr: the caller must see false")
        #expect(b.lastStatus == OSStatus(eventHotKeyExistsErr))
        #expect(a.lastStatus == noErr)
    }

    // MARK: - A refused shortcut is visible and retried

    private func model(hotkey: FakeHotkey) -> ClipboardModel {
        let td = TempDefaults()
        td.defaults.set("option+command:9", forKey: "pastePlainShortcut")
        td.defaults.set(true, forKey: "pastePlainEnabled")
        return ClipboardModel(dataDirectory: makeTempDir(), pasteboard: makePasteboard(),
                              settings: { ClipboardSettings(defaults: td.defaults) },
                              accessibilityTrusted: { true }, sendPaste: { .posted }, notify: { _ in }, hotkey: hotkey)
    }

    @Test func aRefusedShortcutSaysSoInFrench() {
        let hotkey = FakeHotkey()
        hotkey.accept = false
        let m = model(hotkey: hotkey)
        m.start()
        defer { m.stop() }
        #expect(m.plainPasteStatus.contains("Raccourci déjà utilisé par une autre app"), "\(m.plainPasteStatus)")
    }

    @Test func activatingTheAppRegistersARefusedShortcutAgain() async throws {
        let hotkey = FakeHotkey()
        hotkey.accept = false
        let m = model(hotkey: hotkey)
        m.start()
        defer { m.stop() }
        #expect(hotkey.registered == nil && hotkey.registerCalls.count == 1)

        hotkey.accept = true   // the other app let go
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try await Task.sleep(for: .milliseconds(150))

        #expect(hotkey.registered?.keyCode == 9, "still not registered after the activation")
        #expect(m.plainPasteStatus.contains("actif"), "\(m.plainPasteStatus)")
    }
}
