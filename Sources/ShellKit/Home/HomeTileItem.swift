import Foundation

/// A feature panel the home can open as a tile (a registered tab). Plain values, so the merge stays pure.
public struct HomeFeature: Equatable, Sendable {
    public let id: String
    public let title: String
    public let systemImage: String

    public init(id: String, title: String, systemImage: String) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
    }
}

/// One tile of the home grid and of the Explorer: a quick action or a feature panel, never both for the same thing.
public struct HomeTileItem: Identifiable, Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        /// A quick action or a panel shortcut of `HomeActionCatalog`.
        case action(HomeAction)
        /// A feature panel that no action covers (Finder, Dock, Écran...): a tap opens its page.
        case feature
    }

    /// The action id, or the feature id for a tile no action covers. This is what the hidden set stores.
    public let id: String
    public let title: String
    public let systemImage: String
    public let source: Source
    /// The feature this tile stands for, when there is one (a quick action such as Capture has none).
    public let featureID: String?
    /// False when the feature is switched off: the tile is shown dimmed and a tap opens the Settings.
    public let isEnabled: Bool
    /// The user hid it from the home. Only the Explorer lists hidden tiles (to bring them back).
    public let isHidden: Bool

    public var action: HomeAction? {
        if case .action(let action) = source { return action }
        return nil
    }
}
