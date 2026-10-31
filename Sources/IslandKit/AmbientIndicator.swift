import Foundation
import IslandUI

/// Which side of the notch (or of the pill) an indicator prefers.
public enum AmbientWing: Sendable {
    case leading, trailing
}

/// The switches the user sees in Settings. Anything else (cleaning countdown, quick-access notice) is an
/// alert: it is never switched off, it only lasts a few seconds.
public enum AmbientChannel {
    public static let limits = "limits"
    public static let claude = "claude"
    public static let music = "music"
    public static let battery = "battery"
    public static let keepAwake = "keepawake"
    public static let alert = "alert"

    /// Default order of the user-facing channels.
    public static let userChoices = [limits, claude, music, battery, keepAwake]

    public static func title(_ channel: String) -> String {
        switch channel {
        case limits: "Limites Claude"
        case claude: "Claude au travail"
        case music: "Lecture en cours"
        case battery: "Batterie"
        case keepAwake: "Maintien d’éveil"
        default: "Alertes"
        }
    }

    public static func hint(_ channel: String) -> String {
        switch channel {
        case limits: "Votre consommation sur la fenêtre de 5 heures ou la semaine."
        case claude: "Le temps écoulé quand Claude travaille, et une alerte quand il attend."
        case music: "Un égaliseur et le titre pendant la lecture."
        case battery: "Le niveau, la charge et une alerte sous 20 %."
        case keepAwake: "Une tasse quand le Mac est maintenu éveillé."
        default: "Toujours affichées."
        }
    }
}

/// One thing the closed island can show: a glyph, an optional short value, a status. Pure data.
public struct AmbientIndicator: Identifiable, Equatable, Sendable {
    public enum Glyph: Equatable, Sendable {
        case symbol
        /// Three animated bars instead of a symbol (music).
        case equalizer
    }

    public let id: String
    /// The Settings switch this indicator belongs to (`AmbientChannel`).
    public var channel: String
    public var symbol: String
    public var text: String?
    public var status: IslandStatus
    /// 0...1 draws a thin ring around the glyph.
    public var progress: Double?
    public var priority: ActivityPriority
    /// Pins the indicator, pulses it once when it appears and tints its text.
    public var isUrgent: Bool
    public var wing: AmbientWing?
    public var glyph: Glyph
    /// An indeterminate ring turns around the glyph (Claude is working).
    public var isBusy: Bool
    /// Shows the time elapsed since this date instead of `text` (ticks once a second in the view).
    public var clockSince: Date?
    /// Spoken by VoiceOver when the visible text is not enough.
    public var label: String?

    public init(id: String, channel: String? = nil, symbol: String, text: String? = nil,
                status: IslandStatus = .neutral, progress: Double? = nil,
                priority: ActivityPriority = .ambient, isUrgent: Bool = false, wing: AmbientWing? = nil,
                glyph: Glyph = .symbol, isBusy: Bool = false, clockSince: Date? = nil, label: String? = nil) {
        self.id = id
        self.channel = channel ?? id
        self.symbol = symbol
        self.text = text
        self.status = status
        self.progress = progress
        self.priority = priority
        self.isUrgent = isUrgent
        self.wing = wing
        self.glyph = glyph
        self.isBusy = isBusy
        self.clockSince = clockSince
        self.label = label
    }

    /// Urgent and live items (an alert, Claude working or waiting) stay put: rotation only moves the rest.
    public var isPinned: Bool { isUrgent || priority >= .claudeWorking }

    /// Color alone never carries the state: VoiceOver gets the status and the value in words.
    public func accessibilityLabel(clock: String? = nil) -> String {
        var parts: [String] = []
        if let label, !label.isEmpty { parts.append(label) }
        let shown = clock ?? text
        if let shown, !shown.isEmpty, shown != label { parts.append(shown) }
        if let word = CompactStrip.statusWord(status), !(label?.contains(word) ?? false) { parts.append(word) }
        if let progress, !(shown?.contains("%") ?? false) { parts.append("\(Int((CompactStrip.clampedProgress(progress) * 100).rounded())) %") }
        return parts.isEmpty ? "Indicateur de l’île" : parts.joined(separator: ", ")
    }
}
