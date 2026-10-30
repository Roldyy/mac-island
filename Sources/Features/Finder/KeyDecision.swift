/// Everything the decision needs to know besides the key itself.
struct FinderKeyContext: Equatable {
    var finderFrontmost: Bool
    var textEditing: Bool
    var hasPendingCut: Bool
    var pasteboardHasFileURLs: Bool
    var pasteboardHasImage: Bool
    var cutPasteEnabled: Bool
    var imagePasteEnabled: Bool
}

enum KeyDecision: Equatable {
    case pass
    case passAndCancelCut
    case swallowCut
    case swallowPasteMove
    case swallowPasteImage
    /// Auto-repeat of a shortcut we own: swallowed so Finder never sees it, no second action.
    case swallowRepeat

    var swallows: Bool {
        switch self {
        case .pass, .passAndCancelCut: false
        case .swallowCut, .swallowPasteMove, .swallowPasteImage, .swallowRepeat: true
        }
    }

    /// Cheap pre-filter run first in the tap callback, so every other key costs one comparison.
    static func isCandidate(_ chord: KeyChord) -> Bool {
        chord.keyCode == KeyCode.x || chord.keyCode == KeyCode.v
            || chord.keyCode == KeyCode.c || chord.keyCode == KeyCode.esc
    }

    /// Pure decision: event + state -> swallow or pass. Only Esc and plain Cmd+C/X/V ever matter.
    static func decide(_ chord: KeyChord, _ ctx: FinderKeyContext) -> KeyDecision {
        guard ctx.finderFrontmost, !ctx.textEditing else { return .pass }
        switch chord.keyCode {
        case KeyCode.esc:
            return chord.noModifiers && ctx.hasPendingCut ? .passAndCancelCut : .pass
        case KeyCode.c:
            return chord.commandOnly && ctx.hasPendingCut ? .passAndCancelCut : .pass
        case KeyCode.x:
            guard chord.commandOnly, ctx.cutPasteEnabled else { return .pass }
            return chord.isRepeat ? .swallowRepeat : .swallowCut
        case KeyCode.v:
            guard chord.commandOnly else { return .pass }
            if ctx.cutPasteEnabled && ctx.hasPendingCut {
                return chord.isRepeat ? .swallowRepeat : .swallowPasteMove
            }
            if ctx.imagePasteEnabled && ctx.pasteboardHasImage && !ctx.pasteboardHasFileURLs {
                return chord.isRepeat ? .swallowRepeat : .swallowPasteImage
            }
            return .pass
        default:
            return .pass
        }
    }
}
