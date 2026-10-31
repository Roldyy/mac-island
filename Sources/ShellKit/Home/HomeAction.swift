import Foundation

/// Something a round button or a tile can do.
public struct HomeAction: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Toggles the Explorer grid.
        case explore
        /// The Settings window.
        case settings
        /// An existing quick-access action (`QuickAccessCatalog` id), fired through `QuickActionTable`.
        case quick(String)
        /// Opens a feature's panel (a tab id) inside the island.
        case page(String)
    }

    public let id: String
    public let title: String
    public let systemImage: String
    /// Icon while a toggle is on (keep awake).
    public let activeSystemImage: String?
    public let kind: Kind

    public init(id: String, title: String, systemImage: String, activeSystemImage: String? = nil, kind: Kind) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.activeSystemImage = activeSystemImage
        self.kind = kind
    }
}

public enum HomeActionCatalog {
    public static let all: [HomeAction] = [
        HomeAction(id: "explore", title: "Explorer", systemImage: "square.grid.2x2", kind: .explore),
        HomeAction(id: "clipboard", title: "Presse-papiers", systemImage: "doc.on.clipboard", kind: .page("clipboard")),
        HomeAction(id: "settings", title: "Réglages…", systemImage: "gearshape", kind: .settings),
        HomeAction(id: "mixer", title: "Mélangeur de volume", systemImage: "speaker.wave.2", kind: .page("audio")),
        HomeAction(id: "commands", title: "Commandes", systemImage: "command", kind: .quick("commands")),
        HomeAction(id: "keepawake", title: "Garder éveillé", systemImage: "cup.and.saucer",
                   activeSystemImage: "cup.and.saucer.fill", kind: .quick("keepawake")),
        HomeAction(id: "capture", title: "Capture", systemImage: "camera.viewfinder", kind: .quick("capture")),
        HomeAction(id: "lockScreen", title: "Verrouiller", systemImage: "lock", kind: .quick("lockScreen")),
        HomeAction(id: "cleaning", title: "Nettoyage", systemImage: "sparkles.rectangle.stack", kind: .quick("cleaning")),
        HomeAction(id: "terminal", title: "Terminal", systemImage: "terminal", kind: .page("terminal")),
        HomeAction(id: "agents", title: "Claude", systemImage: "sparkles", kind: .page("agents")),
        HomeAction(id: "shelf", title: "Étagère", systemImage: "tray.full", kind: .page("shelf")),
        HomeAction(id: "nowplaying", title: "Lecture", systemImage: "music.note", kind: .page("nowplaying")),
        HomeAction(id: "monitor", title: "Moniteur", systemImage: "gauge.with.dots.needle.50percent", kind: .page("monitor")),
        HomeAction(id: "fans", title: "Ventilos", systemImage: "fan", kind: .page("fans")),
    ]

    /// Ids a layout saved by another build may carry; they map to the action that does the same here.
    static let aliases: [String: String] = [
        "control.keepAwake": "keepawake", "controls": "commands", "music": "nowplaying",
        "control.commandBar": "commands", "control.screenshot": "capture", "control.mixer": "mixer",
    ]

    public static func resolve(_ id: String) -> String? {
        let mapped = aliases[id] ?? id
        return all.contains { $0.id == mapped } ? mapped : nil
    }

    public static func action(_ id: String) -> HomeAction? {
        let mapped = aliases[id] ?? id
        return all.first { $0.id == mapped }
    }

    /// The tiles of the home grid, in order; the mode decides how many rows show.
    public static let tileIDs = [
        "mixer", "keepawake", "agents", "commands",
        "capture", "lockScreen", "cleaning", "monitor",
        "shelf", "clipboard", "terminal", "nowplaying",
    ]
}
