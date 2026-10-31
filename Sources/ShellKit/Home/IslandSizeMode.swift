import Foundation

/// Compacte / Spacieuse / Personnalisé: the three sizes of the open island.
public enum IslandSizeMode: String, CaseIterable, Identifiable, Sendable {
    case compact, spacious, custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .compact: "Compacte"
        case .spacious: "Spacieuse"
        case .custom: "Personnalisé"
        }
    }

    public var systemImage: String {
        switch self {
        case .compact: "rectangle.compress.vertical"
        case .spacious: "rectangle.expand.vertical"
        case .custom: "arrow.up.left.and.arrow.down.right"
        }
    }
}
