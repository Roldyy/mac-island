import Foundation

/// One thing a chip can do when tapped (open the Monitor, copy the IP, quit an app...).
///
/// `isDestructive` styles the button as destructive; a destructive action, or one with `requiresConfirmation`, needs
/// a second click ("Confirmer") that expires after `StatusChipConfirmation.window`. Equality ignores `handler`, so
/// two readings that only differ by a closure do not redraw the row.
public struct StatusChipAction: Identifiable, Equatable {
    public let id: String
    /// French title of the button.
    public var title: String
    public var systemImage: String?
    public var isDestructive: Bool
    public var requiresConfirmation: Bool
    public var handler: @MainActor () -> Void

    public init(id: String? = nil, title: String, systemImage: String? = nil, isDestructive: Bool = false,
                requiresConfirmation: Bool = false, handler: @escaping @MainActor () -> Void) {
        self.id = id ?? title
        self.title = title
        self.systemImage = systemImage
        self.isDestructive = isDestructive
        self.requiresConfirmation = requiresConfirmation
        self.handler = handler
    }

    /// Destructive implies a confirmation: the row never runs one on a single click.
    public var needsConfirmation: Bool { isDestructive || requiresConfirmation }

    public static func == (lhs: StatusChipAction, rhs: StatusChipAction) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.systemImage == rhs.systemImage
            && lhs.isDestructive == rhs.isDestructive && lhs.requiresConfirmation == rhs.requiresConfirmation
    }
}
