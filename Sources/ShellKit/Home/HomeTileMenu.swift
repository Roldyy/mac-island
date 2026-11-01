import Foundation

/// What the right-click menus of the home offer for tiles. Pure, so the wording and the rules are tested.
enum HomeTileMenu {
    enum Entry: Equatable {
        case hide, show

        var title: String {
            switch self {
            case .hide: "Masquer ce raccourci"
            case .show: "Afficher le raccourci"
            }
        }

        var systemImage: String {
            switch self {
            case .hide: "eye.slash"
            case .show: "eye"
            }
        }
    }

    /// A hidden tile (listed in the Explorer) offers to come back; any other offers to leave.
    static func entries(for item: HomeTileItem) -> [Entry] { [item.isHidden ? .show : .hide] }

    static let showAllTitle = "Tout afficher"

    /// "Tout afficher" in the island menu is only live when something is hidden.
    static func showAllEnabled(hidden: Set<String>) -> Bool { !hidden.isEmpty }
}
