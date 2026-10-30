import Foundation
import os

/// Everything the tap thread may know about the cut, as plain values. Pure: the clock and the
/// pasteboard change count come in as arguments.
struct FinderKeySnapshot: Equatable, Sendable {
    var finderFrontmost = false
    var cutExpiresAt: Date?
    var cutPasteboardChangeCount: Int?
    /// Cmd+X pressed, Finder not answered yet: Cmd+V typed right after must already be ours.
    var inFlightCuts = 0
    var cutPasteEnabled = false
    var imagePasteEnabled = false

    func hasPendingCut(now: Date, pasteboardChangeCount: Int) -> Bool {
        if inFlightCuts > 0 { return true }
        guard let cutExpiresAt, now <= cutExpiresAt else { return false }
        if let mine = cutPasteboardChangeCount, mine != pasteboardChangeCount { return false }
        return true
    }

    /// The cheap pre-filter of the tap thread: keycode, modifiers and a few flags, no Accessibility,
    /// no pasteboard read. False means the key is none of our business.
    func needsFullDecision(_ chord: KeyChord, now: Date, pasteboardChangeCount: Int) -> Bool {
        guard finderFrontmost, KeyDecision.isCandidate(chord) else { return false }
        let pending = hasPendingCut(now: now, pasteboardChangeCount: pasteboardChangeCount)
        switch chord.keyCode {
        case KeyCode.x: return chord.commandOnly && cutPasteEnabled
        case KeyCode.v: return chord.commandOnly && ((cutPasteEnabled && pending) || imagePasteEnabled)
        case KeyCode.c: return chord.commandOnly && pending
        case KeyCode.esc: return chord.noModifiers && pending
        default: return false
        }
    }

    /// The state change that goes with a decision, applied at once on the tap thread.
    mutating func apply(_ decision: KeyDecision) {
        switch decision {
        case .swallowCut:
            inFlightCuts += 1
        case .passAndCancelCut:
            cutExpiresAt = nil
            cutPasteboardChangeCount = nil
        case .pass, .swallowPasteMove, .swallowPasteImage, .swallowRepeat:
            break
        }
    }
}

/// The snapshot behind an unfair lock: the tap thread reads it, the main actor writes it.
final class FinderKeyState: Sendable {
    private let box = OSAllocatedUnfairLock(initialState: FinderKeySnapshot())
    func read() -> FinderKeySnapshot { box.withLock { $0 } }
    func update(_ body: @Sendable (inout FinderKeySnapshot) -> Void) { box.withLock { body(&$0) } }
}

/// The synchronous swallow-or-pass decision, callable from any thread.
struct FinderKeyEvaluator: Sendable {
    let environment: FinderEnvironment
    let pasteboard: PasteboardReading
    let state: FinderKeyState
    let clock: @Sendable () -> Date

    func decide(_ chord: KeyChord) -> KeyDecision {
        let snapshot = state.read()
        // Cheapest tests first: a flag and a keycode. Only a Finder-frontmost candidate key goes further.
        guard snapshot.finderFrontmost, KeyDecision.isCandidate(chord) else { return .pass }
        let now = clock()
        let changeCount = pasteboard.changeCount
        guard snapshot.needsFullDecision(chord, now: now, pasteboardChangeCount: changeCount),
              let finder = environment.finderPID() else { return .pass }
        // Frontmost alone is not trust: the Accessibility focus must be in Finder too.
        guard FinderFocus.ownsKeyboard(finderFrontmost: snapshot.finderFrontmost,
                                       focusedAppPID: environment.focusedApplicationPID(), finderPID: finder)
        else { return .pass }
        let isPaste = chord.keyCode == KeyCode.v
        let ctx = FinderKeyContext(
            finderFrontmost: true,
            textEditing: environment.isTextEditing(finderPID: finder),
            hasPendingCut: snapshot.hasPendingCut(now: now, pasteboardChangeCount: changeCount),
            pasteboardHasFileURLs: isPaste ? pasteboard.hasFileURLs : false,
            pasteboardHasImage: isPaste ? pasteboard.hasImage : false,
            cutPasteEnabled: snapshot.cutPasteEnabled, imagePasteEnabled: snapshot.imagePasteEnabled)
        return KeyDecision.decide(chord, ctx)
    }

    /// `decide` plus its state change, for the tap thread.
    func decideApplying(_ chord: KeyChord) -> KeyDecision {
        let d = decide(chord)
        state.update { $0.apply(d) }
        return d
    }
}
