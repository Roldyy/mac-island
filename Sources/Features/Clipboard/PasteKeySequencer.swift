import ApplicationServices
import Carbon.HIToolbox
import Foundation

enum PasteSendResult: Equatable {
    case posted
    case eventFailed        // the key events could not even be created
}

/// Sends the synthetic Cmd+V once the user's fingers are off the shortcut.
///
/// The hotkey fires on key DOWN, so Option and Command are still physically held. A Cmd+V posted
/// while Option is down reaches the target as Option+Cmd+V (no paste, "Paste and Match Style",
/// Finder "Move Item Here"). So: poll the physical modifiers until they are all up (about 1 s at most),
/// then post a key pair whose flags are EXACTLY Command, from a private event source that does not
/// inherit the held modifiers. No modifier release is ever faked.
@MainActor
struct PasteKeySequencer {
    static let pollInterval: Duration = .milliseconds(10)
    static let maxPolls = 100
    static let postedFlags: CGEventFlags = .maskCommand

    var modifiersHeld: () -> Bool
    var sleep: (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    var post: (CGEventFlags) -> Bool

    static func live() -> PasteKeySequencer {
        PasteKeySequencer(modifiersHeld: { PasteKeySequencer.physicalModifiersHeld() },
                          post: { PasteKeySequencer.postV(flags: $0) })
    }

    func run() async -> PasteSendResult {
        let start = ContinuousClock.now
        var polls = 0
        var held = modifiersHeld()
        while held && polls < Self.maxPolls {
            await sleep(Self.pollInterval)
            polls += 1
            held = modifiersHeld()
        }
        let waited = ContinuousClock.now - start
        let ms = Int(waited.components.seconds * 1000 + waited.components.attoseconds / 1_000_000_000_000_000)
        if held {
            PasteLog.logger.notice("modifiers still held after \(ms, privacy: .public) ms: posting with cleared flags anyway")
        } else {
            PasteLog.logger.notice("modifiers released after \(ms, privacy: .public) ms")
        }
        let ok = post(Self.postedFlags)
        PasteLog.logger.notice("event posted: \(ok, privacy: .public)")
        return ok ? .posted : .eventFailed
    }

    // MARK: - Live system calls

    nonisolated static func physicalModifiersHeld() -> Bool {
        let mask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        return !CGEventSource.flagsState(.combinedSessionState).intersection(mask).isEmpty
    }

    /// V down + V up with explicit flags, to the HID tap. The private source starts from no modifiers, so a
    /// held Option cannot leak into the event.
    nonisolated static func postV(flags: CGEventFlags) -> Bool {
        let source = CGEventSource(stateID: .privateState)
        let v = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false) else { return false }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
