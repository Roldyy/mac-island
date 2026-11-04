import Foundation
import IslandUI

/// What one chip shows right now. A value: a source builds a new one whenever something worth redrawing changed.
public struct StatusChipReading: Identifiable, Equatable {
    public enum Level: Int, Comparable, Sendable {
        case normal, attention, alert

        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }

        /// The design-system status the chip takes its tint from.
        public var status: IslandStatus {
            switch self {
            case .normal: .neutral
            case .attention: .warning
            case .alert: .danger
            }
        }

        /// Spoken by VoiceOver; empty for a normal chip.
        public var spokenWord: String {
            switch self {
            case .normal: ""
            case .attention: "Attention"
            case .alert: "Alerte"
            }
        }
    }

    public var kind: StatusChipKind
    public var id: StatusChipKind { kind }
    /// Main text, short (the chip has no room): "Wi-Fi", "23 %", "412 Go".
    public var primary: String
    /// Dimmer text after it, optional: "↓ 1,2 Mo/s".
    public var secondary: String?
    /// SF Symbol.
    public var symbol: String
    public var level: Level
    /// 0...1 draws a ring in place of the symbol (the timer); nil draws the symbol.
    public var progress: Double?
    /// Shown in a popover when the chip is tapped; empty means the chip is not tappable.
    public var actions: [StatusChipAction]

    public init(kind: StatusChipKind, primary: String, secondary: String? = nil, symbol: String? = nil,
                level: Level = .normal, progress: Double? = nil, actions: [StatusChipAction] = []) {
        self.kind = kind
        self.primary = primary
        self.secondary = secondary
        self.symbol = symbol ?? kind.symbol
        self.level = level
        self.progress = progress.flatMap { $0.isFinite ? min(max($0, 0), 1) : nil }
        self.actions = actions
    }

    /// "Réseau : Wi-Fi, ↓ 1,2 Mo/s. Attention."
    public var accessibilityText: String {
        var text = "\(kind.title) : \(primary)"
        if let secondary, !secondary.isEmpty { text += ", \(secondary)" }
        if !level.spokenWord.isEmpty { text += ". \(level.spokenWord)" }
        return text
    }
}
