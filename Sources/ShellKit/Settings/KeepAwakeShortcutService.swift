import AppKit
import Carbon.HIToolbox
import Foundation
import Observation

/// Registers the global "Garder éveillé" shortcut with Carbon (no permission needed).
/// Nothing registers until the app calls `arm(action:)` once at launch; until then the Settings page says so.
@MainActor @Observable
public final class KeepAwakeShortcutService {
    public static let shared = KeepAwakeShortcutService()

    public static let enabledKey = "keepAwakeShortcutEnabled"
    public static let shortcutKey = "keepAwakeShortcut"

    /// True once an action is set; false means the page must not claim the shortcut works.
    public private(set) var isArmed = false
    /// True while the system holds the registration (it can be refused when another app owns the keys).
    public private(set) var isRegistered = false

    @ObservationIgnored private var action: (@MainActor () -> Void)?
    @ObservationIgnored private var defaults: UserDefaults?
    @ObservationIgnored private var hotKey: EventHotKeyRef?
    @ObservationIgnored private var handler: EventHandlerRef?

    public init() {}

    public static func enabled(in defaults: UserDefaults) -> Bool {
        (defaults.object(forKey: enabledKey) as? Bool) ?? true
    }

    public static func shortcut(in defaults: UserDefaults) -> ShortcutSpec {
        defaults.string(forKey: shortcutKey).flatMap(ShortcutSpec.parse) ?? .keepAwakeDefault
    }

    /// Call once at launch with what the shortcut does (e.g. toggle keep awake).
    public func arm(defaults: UserDefaults, action: @escaping @MainActor () -> Void) {
        self.defaults = defaults
        self.action = action
        isArmed = true
        refresh()
    }

    /// Re-reads the settings and registers, moves or drops the hotkey. Safe to call after every change.
    public func refresh() {
        unregister()
        guard isArmed, let defaults, Self.enabled(in: defaults) else { return }
        register(Self.shortcut(in: defaults))
    }

    private func register(_ spec: ShortcutSpec) {
        if handler == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let pointer = Unmanaged.passUnretained(self).toOpaque()
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
                guard let userData else { return noErr }
                let service = Unmanaged<KeepAwakeShortcutService>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in service.fire() }
                return noErr
            }, 1, &eventType, pointer, &handler)
            guard status == noErr else { return }
        }
        let id = EventHotKeyID(signature: OSType(0x4D49_534B), id: 1)  // 'MISK'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(spec.keyCode, spec.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKey = ref
            isRegistered = true
        }
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        isRegistered = false
    }

    private func fire() { action?() }
}
