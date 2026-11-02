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
    /// The time: the fixed center of the pill on a screen without a notch, the first item of the left wing with one.
    public static let clock = "clock"
    /// Processor load and memory in use.
    public static let system = "system"
    public static let network = "network"
    public static let disk = "disk"
    public static let mic = "mic"
    public static let camera = "camera"
    /// A bar and a percentage for a second when the system volume changes.
    public static let volume = "volume"
    /// The Compagnon (mascot), an opt-in indicator posted only while its feature is on. Not a user choice of the closed
    /// island list (`userChoices`): the feature's own switch in Fonctions is the opt-in, so `isEnabled` is always true.
    public static let mascot = "mascot"

    /// Default order of the user-facing channels.
    public static let userChoices = [limits, claude, music, battery, keepAwake, clock, system, network, disk, mic, camera, volume]

    /// On out of the box. The rest is opt-in so the pill is not cluttered.
    /// What Harold asked for and nothing else: Claude, the clock, the battery and the keep-awake cup. Music, the
    /// system (CPU, memory) and the network are choices in Settings, off until switched on.
    public static let defaultOn: Set<String> = [limits, claude, battery, keepAwake, clock]

    public static func title(_ channel: String) -> String {
        switch channel {
        case limits: "Limites Claude"
        case claude: "Claude au travail"
        case music: "Lecture en cours"
        case battery: "Batterie"
        case keepAwake: "Maintien d’éveil"
        case clock: "Heure au centre"
        case system: "Processeur et mémoire"
        case network: "Réseau"
        case disk: "Espace disque"
        case mic: "Micro actif"
        case camera: "Caméra active"
        case volume: "Volume"
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
        case clock: "L’heure au centre de l’île, et la date quand il y a de la place. Avec une encoche, l’heure ouvre l’aile gauche."
        case system: "La charge du processeur et la mémoire utilisée, avec un point de couleur pour la pression mémoire."
        case network: "Le débit descendant et montant, le type de connexion et un repère quand un VPN est actif."
        case disk: "L’espace libre sur le disque de démarrage."
        case mic: "Un point orange tant qu’une application utilise le micro."
        case camera: "Un point vert tant qu’une application utilise la caméra."
        case volume: "Une barre et le pourcentage pendant une seconde et demie quand le volume change."
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
        /// No glyph at all: the value stands alone (the clock).
        case none
        /// The animated companion, drawn by `AmbientMascotSlot` (14 pt, no text).
        case mascot
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
    /// A second, quieter text after `text` (the short date next to the time). Only the pill's center shows it.
    public var detail: String?
    /// 0...1 draws a thin bar between the glyph and the text (the volume).
    public var bar: Double?
    /// Drawn quieter: the value is old (a plan reading of hours ago). Never carries meaning alone.
    public var isDimmed: Bool
    /// A small state dot on the glyph (a Claude session is open). Its meaning is also in `label`.
    public var badge: IslandStatus?

    public init(id: String, channel: String? = nil, symbol: String, text: String? = nil,
                status: IslandStatus = .neutral, progress: Double? = nil,
                priority: ActivityPriority = .ambient, isUrgent: Bool = false, wing: AmbientWing? = nil,
                glyph: Glyph = .symbol, isBusy: Bool = false, clockSince: Date? = nil, label: String? = nil,
                detail: String? = nil, bar: Double? = nil, isDimmed: Bool = false, badge: IslandStatus? = nil) {
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
        self.detail = detail
        self.bar = bar
        self.isDimmed = isDimmed
        self.badge = badge
    }

    /// Channels whose glyph is itself the information: Claude working or waiting, the keep-awake cup, the mic and
    /// camera dots, an alert. Their colour is never the only signal (`label` says it).
    /// The battery is one: its outline fills with the charge, so it says the level without a percentage (a wing
    /// that is too narrow drops the percentage, never the battery).
    static let stateChannels: Set<String> = [AmbientChannel.claude, AmbientChannel.keepAwake, AmbientChannel.mic,
                                             AmbientChannel.camera, AmbientChannel.alert, AmbientChannel.battery]

    /// An indicator is drawn only with something to read: a value, a clock, a bar, a ring, the equalizer of a track
    /// that is playing, or a state that means something on its own. A bare glyph (an arrow with no rate, a chip with
    /// no load) is never drawn.
    public var isReadable: Bool {
        if let text, !text.isEmpty { return true }
        if clockSince != nil || bar != nil || progress != nil || badge != nil { return true }
        if glyph == .equalizer { return true }
        // The companion is the whole point of its indicator: it is only ever posted while its feature is on.
        if glyph == .mascot { return true }
        if Self.stateChannels.contains(channel) { return true }
        // Offline: the struck-through symbol, in the warning colour, with its words for VoiceOver.
        return channel == AmbientChannel.network && status == .warning
    }

    /// Urgent and live items (an alert, Claude working or waiting) stay put: rotation only moves the rest.
    /// The companion stays put too: rotating it away every four seconds would make it appear half the time.
    public var isPinned: Bool { isUrgent || priority >= .claudeWorking || glyph == .mascot }

    /// Color alone never carries the state: VoiceOver gets the status and the value in words.
    public func accessibilityLabel(clock: String? = nil) -> String {
        var parts: [String] = []
        if let label, !label.isEmpty { parts.append(label) }
        let shown = clock ?? text
        if let shown, !shown.isEmpty, shown != label { parts.append(shown) }
        if let detail, !detail.isEmpty { parts.append(detail) }
        if let word = CompactStrip.statusWord(status), !(label?.contains(word) ?? false) { parts.append(word) }
        if let progress, !(shown?.contains("%") ?? false) { parts.append("\(Int((CompactStrip.clampedProgress(progress) * 100).rounded())) %") }
        return parts.isEmpty ? "Indicateur de l’île" : parts.joined(separator: ", ")
    }
}
