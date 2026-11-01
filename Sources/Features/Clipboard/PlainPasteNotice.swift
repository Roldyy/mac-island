import IslandKit

/// The short French line shown in the closed island when a plain paste cannot be performed.
enum PlainPasteNotice: Equatable {
    case needsPermission
    case nothingToPaste
    case eventFailed

    static let noticeID = "clipboard.plainpaste.notice"

    /// Same wording as `QuickActionNotice.pastePlainNeedsAccess` (ShellKit, which this target cannot import).
    var text: String {
        switch self {
        case .needsPermission: "Autorisation requise : Surveillance de l'entrée / Accessibilité"
        case .nothingToPaste: "Collage sans style : rien à coller (pas de texte)"
        case .eventFailed: "Collage sans style impossible : événement clavier refusé"
        }
    }

    @MainActor
    static func post(_ notice: PlainPasteNotice, center: ActivityCenter? = nil) {
        (center ?? ActivityCenter.shared).post(IslandActivity(id: noticeID, source: "clipboard", priority: .alert,
                                   leading: CompactItem(symbol: "exclamationmark.triangle.fill",
                                                        text: notice.text, status: .warning)),
                    expiresAfter: .seconds(4))
    }
}
