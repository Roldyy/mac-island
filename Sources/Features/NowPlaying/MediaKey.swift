import AppKit
import CoreGraphics

/// NX_KEYTYPE_* codes of the system media keys.
enum MediaKey: Int, Sendable {
    case playPause = 16
    case next = 17
    case previous = 18
}

/// Pure composition of the NSEvent `systemDefined` (subtype 8) payload.
enum MediaKeyEvent {
    struct Parts: Equatable {
        var subtype: Int
        var modifierFlags: UInt
        var data1: Int
    }

    /// data1 = keyCode << 16 | (0xA down / 0xB up) << 8
    static func compose(_ key: MediaKey, down: Bool) -> Parts {
        let state = down ? 0xA : 0xB
        return Parts(subtype: 8, modifierFlags: UInt(state << 8), data1: (key.rawValue << 16) | (state << 8))
    }

    /// Posts press then release to the HID event tap. Compile-only in tests.
    static func post(_ key: MediaKey) {
        for down in [true, false] {
            let p = compose(key, down: down)
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: p.modifierFlags),
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: Int16(p.subtype), data1: p.data1, data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
