import Foundation

/// Island panels that are shown only while a feature switch is on, and that are gated by a switch other than their own id.
///
/// The ported panels (Musique, Minuteur, Téléchargements...) keep the id the ported lanes gave them, while the
/// registry's switch has another name (`notchTimer`, `notchDownloads`...). This table is the one place that says which
/// switch (or switches: any one on is enough) opens which panel. A panel in the table is OPTIONAL: while all its
/// switches are off it has no tile at all (the 12 first panels keep their dimmed tile).
public struct ShellTabGate: Equatable, Sendable {
    /// tab id -> registry ids; the panel is on when any of them is on.
    public let features: [String: [String]]

    public init(_ features: [String: [String]] = [:]) { self.features = features }

    public static let none = ShellTabGate()

    /// The panels of the lane E and lane F tabs, with the switches of Settings > Fonctionnalités that open them.
    public static let ported = ShellTabGate([
        "music": ["notchLyrics", "notchQueue", "notchLiveEqualizer"],
        "timer": ["notchTimer"],
        "calendar": ["notchCalendar"],
        "notifications": ["notchNotifications"],
        "accessories": ["notchAccessories"],
        "downloads": ["notchDownloads"],
        "filetools": ["mediaTools"],
        "watch": ["notchWatch"],
        "mirror": ["cameraPreview"],
        "companion": ["notchMascot"],
    ])

    public func isOptional(_ tabID: String) -> Bool { features[tabID] != nil }

    /// A gated panel is on when one of its switches is; any other panel follows the switch of its own id.
    public func isEnabled(_ tabID: String, enabled: (String) -> Bool) -> Bool {
        guard let ids = features[tabID] else { return enabled(tabID) }
        return ids.contains(where: enabled)
    }
}
