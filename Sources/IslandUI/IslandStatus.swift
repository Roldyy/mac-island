import SwiftUI

/// Status colors always travel with a symbol, so color is never the only signal.
public enum IslandStatus: String, CaseIterable, Sendable {
    case neutral, info, success, warning, danger

    public var symbol: String {
        switch self {
        case .neutral: "circle"
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .danger: "xmark.octagon.fill"
        }
    }

    public var color: Color { IslandPalette.status(self).color }

    /// Spoken by VoiceOver next to the symbol.
    public var label: String {
        switch self {
        case .neutral: "Neutre"
        case .info: "Information"
        case .success: "Réussi"
        case .warning: "Attention"
        case .danger: "Erreur"
        }
    }
}
