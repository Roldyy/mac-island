import Carbon.HIToolbox
import Foundation
import Testing
@testable import ShellKit

/// Regression for "Option+Command+V does nothing" (third report): every Carbon handler on the application target
/// sees EVERY hotkey press, most recently installed first. Keep Awake's handler used to return `noErr` without
/// reading the `EventHotKeyID`, so once it was installed (at launch, right after the clipboard feature registered its
/// own handler) it swallowed the plain-paste and history presses, and toggled Keep Awake instead.
@MainActor
@Suite(.serialized) struct HotkeyHandlerChainTests {
    /// Counts what reaches it, answers `noErr` (as a feature's handler does for its own key).
    final class Probe {
        var seen: [EventHotKeyID] = []
        var ref: EventHandlerRef?
    }

    static func installProbe(_ probe: Probe) {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(probe).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            Unmanaged<Probe>.fromOpaque(userData).takeUnretainedValue().seen.append(id)
            return noErr
        }, 1, &spec, pointer, &probe.ref)
    }

    /// What the system does on a press: a `kEventHotKeyPressed` event with the key's id, sent to the application.
    @discardableResult
    static func press(signature: OSType, id: UInt32) -> OSStatus {
        var event: EventRef?
        CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, 0, &event)
        var hotKeyID = EventHotKeyID(signature: signature, id: id)
        SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                          MemoryLayout<EventHotKeyID>.size, &hotKeyID)
        let status = SendEventToEventTarget(event, GetApplicationEventTarget())
        if let event { ReleaseEvent(event) }
        return status
    }

    final class Counter { var value = 0 }

    private func armedService(action: @escaping @MainActor () -> Void) -> (KeepAwakeShortcutService, UserDefaults, String) {
        let suite = "keepawake-chain-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        // An unusual combination: the test registers it for real and must not clash with a user's key.
        defaults.set("control+option+shift+command:5", forKey: KeepAwakeShortcutService.shortcutKey)
        let service = KeepAwakeShortcutService()
        service.arm(defaults: defaults, action: action)
        return (service, defaults, suite)
    }

    @Test func keepAwakeLetsAnotherFeaturesKeyPassToTheNextHandler() async throws {
        let probe = Probe()
        Self.installProbe(probe)              // installed first: it runs AFTER Keep Awake's handler
        defer { if let ref = probe.ref { RemoveEventHandler(ref) } }
        let fired = Counter()
        let (service, defaults, suite) = armedService { fired.value += 1 }
        defer { service.disarm(); defaults.removePersistentDomain(forName: suite) }
        #expect(service.isArmed)

        // 'MICL' id 1 is the plain-paste key.
        Self.press(signature: 0x4D49_434C, id: 1)
        try await Task.sleep(for: .milliseconds(150))

        #expect(probe.seen.count == 1, "the press never got past Keep Awake's handler")
        #expect(probe.seen.first?.signature == 0x4D49_434C)
        #expect(fired.value == 0, "Keep Awake toggled on a key that is not its own")
    }

    @Test func keepAwakeStillAnswersItsOwnKey() async throws {
        let probe = Probe()
        Self.installProbe(probe)
        defer { if let ref = probe.ref { RemoveEventHandler(ref) } }
        let fired = Counter()
        let (service, defaults, suite) = armedService { fired.value += 1 }
        defer { service.disarm(); defaults.removePersistentDomain(forName: suite) }

        Self.press(signature: 0x4D49_534B, id: 1)   // 'MISK'
        try await Task.sleep(for: .milliseconds(150))

        #expect(fired.value == 1)
        #expect(probe.seen.isEmpty, "its own key is handled there and stops")
    }
}
