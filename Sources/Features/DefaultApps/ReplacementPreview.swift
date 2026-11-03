import Foundation

/// One change the preview lists: what it touches, what it is now, what it becomes.
public struct PreviewItem: Identifiable, Equatable, Sendable {
    public let kind: ChangeKind
    /// Lower-case UTI or scheme.
    public let identifier: String
    public let title: String
    public let extensions: [String]
    public let previousBundleID: String?
    public let previousName: String?
    public let isProtected: Bool
    /// True when the user picked this protected item on purpose (never set for an unprotected one).
    public let explicitlyPicked: Bool

    public var id: String { "\(kind.rawValue):\(identifier)" }

    public init(kind: ChangeKind, identifier: String, title: String, extensions: [String] = [],
                previousBundleID: String?, previousName: String?, isProtected: Bool, explicitlyPicked: Bool) {
        self.kind = kind
        self.identifier = identifier
        self.title = title
        self.extensions = extensions
        self.previousBundleID = previousBundleID
        self.previousName = previousName
        self.isProtected = isProtected
        self.explicitlyPicked = explicitlyPicked
    }
}

public enum RefusalReason: Equatable, Sendable {
    /// A protected type or scheme the user did not pick on purpose.
    case protectedItem
    /// The replacement does not declare that it can open it.
    case replacementCannotOpen
    /// The replacement already is the default.
    case alreadyDefault

    public var text: String {
        switch self {
        case .protectedItem: "Type protégé : jamais changé sans choix explicite."
        case .replacementCannotOpen: "L’application choisie ne déclare pas pouvoir l’ouvrir."
        case .alreadyDefault: "Déjà ouvert par l’application choisie."
        }
    }
}

public struct RefusedItem: Identifiable, Equatable, Sendable {
    public let kind: ChangeKind
    public let identifier: String
    public let title: String
    public let reason: RefusalReason
    public var id: String { "\(kind.rawValue):\(identifier)" }
}

/// What will change if the user confirms: nothing is written before that.
public struct ReplacementPreview: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sourceName: String?
    public let replacement: AppProfile
    public let items: [PreviewItem]
    public let refused: [RefusedItem]

    public init(id: UUID = UUID(), sourceName: String?, replacement: AppProfile, items: [PreviewItem], refused: [RefusedItem]) {
        self.id = id
        self.sourceName = sourceName
        self.replacement = replacement
        self.items = items
        self.refused = refused
    }
}
