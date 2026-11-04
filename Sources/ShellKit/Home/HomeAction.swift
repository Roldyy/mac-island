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
        // The Éveil page itself (timers, options); "keepawake" above is the one-tap toggle.
        HomeAction(id: "awake", title: "Éveil", systemImage: "moon.zzz", kind: .page("keepawake")),
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

    /// Prefixes of the ids `ShellContext.dockCatalog()` hands out.
    static let dockPrefixes = ["nav.", "tab.", "quick.", "feature.", "settings.", "app.", "port.", "scene."]

    /// True for the shape of a dock-catalog id ("tab.terminal", "port.ocr"). The pure layer cannot know which ones
    /// exist right now (the app registers some at launch), so it keeps any well-formed one.
    public static func isDockID(_ id: String) -> Bool {
        dockPrefixes.contains { id.hasPrefix($0) && id.count > $0.count }
    }

    /// The dock-catalog id of the same command, for a legacy round-button id ("terminal" -> "tab.terminal").
    public static func dockID(forLegacy id: String) -> String? {
        guard let action = action(id) else { return nil }
        switch action.kind {
        case .explore: return "nav.explore"
        case .settings: return "nav.settings"
        case .quick(let quickID): return "quick.\(quickID)"
        case .page(let tabID): return "tab.\(tabID)"
        }
    }

    /// The form a round button stores: the legacy id when the action has one (the stored layout stays readable by
    /// older builds), otherwise the dock id. Nil for an unknown id.
    public static func stored(_ id: String) -> String? {
        if let legacy = resolve(id) { return legacy }
        guard isDockID(id) else { return nil }
        return all.first { dockID(forLegacy: $0.id) == id }?.id ?? id
    }

    /// One identity per command, whichever form it is stored in: the dock id.
    public static func identity(of id: String) -> String? {
        guard let form = stored(id) else { return nil }
        return dockID(forLegacy: form) ?? form
    }

    public static func resolve(_ id: String) -> String? {
        let mapped = aliases[id] ?? id
        return all.contains { $0.id == mapped } ? mapped : nil
    }

    public static func action(_ id: String) -> HomeAction? {
        let mapped = aliases[id] ?? id
        return all.first { $0.id == mapped }
    }

    /// The tiles the user's grid starts with, in order. `HomeTileCatalog` appends every other feature after them.
    public static let tileIDs = [
        "mixer", "keepawake", "agents", "commands",
        "capture", "lockScreen", "cleaning", "monitor",
        "shelf", "clipboard", "terminal", "nowplaying",
        "awake", "settings",
    ]
}
