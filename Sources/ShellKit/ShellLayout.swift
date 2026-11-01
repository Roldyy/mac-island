import Foundation

/// One daily page of the island: a feature tab with its own Home tile, route and header title.
public struct ShellSection: Identifiable, Equatable, Sendable {
    /// Tab id of the feature module; also its feature id.
    public let id: String
    public let title: String
}

/// The island's daily pages, one per need (no grouped pages, no segmented switch).
/// Pure data plus lookups, so the layout is testable without a view.
public enum ShellLayout {
    public static let pages: [ShellSection] = [
        ShellSection(id: "terminal", title: "Terminal"), ShellSection(id: "agents", title: "Claude"),
        ShellSection(id: "clipboard", title: "Presse-papiers"), ShellSection(id: "shelf", title: "Étagère"),
        ShellSection(id: "nowplaying", title: "Lecture"), ShellSection(id: "audio", title: "Mixer"),
        ShellSection(id: "keepawake", title: "Éveil"),
        ShellSection(id: "monitor", title: "Moniteur"), ShellSection(id: "fans", title: "Ventilos"),
    ]

    public static func isDailyPage(_ tabID: String) -> Bool { pages.contains { $0.id == tabID } }

    /// Feature tabs that are not one of the daily pages (reached from the Settings window instead).
    public static func tabsOutsidePages(_ tabIDs: [String]) -> [String] {
        tabIDs.filter { !isDailyPage($0) }
    }

    // MARK: - Explorer

    /// Tabs the Explorer grid lists: the daily pages first in island order, then the rest, enabled only.
    public static func exploreTabIDs(available: [String], isEnabled: (String) -> Bool) -> [String] {
        let grouped = pages.map(\.id).filter(available.contains)
        let others = available.filter { !grouped.contains($0) }
        return (grouped + others).filter(isEnabled)
    }

    // MARK: - Open size

    /// Solid band at the top of the open island, behind the hardware notch; the header starts under it.
    public static let topBandHeight: CGFloat = 38

    /// Height the open island asks for when no section is known (or the section has no entry).
    public static let defaultOpenHeight: CGFloat = 420
    /// Content-driven heights: a terminal needs room, a now-playing card does not.
    static let openHeights: [String: CGFloat] = [
        "terminal": 480, "agents": 560, "clipboard": 420, "shelf": 400,
        "nowplaying": 320, "audio": 380, "keepawake": 320, "monitor": 360, "fans": 380,
        // Ported panels (lanes E and F): the player carries lyrics and the queue under it.
        "music": 480, "timer": 380, "calendar": 400, "notifications": 380, "accessories": 340,
        "downloads": 380, "filetools": 400, "watch": 380, "mirror": 380, "companion": 420,
    ]

    /// Panel height for the visible section; `IslandController` clamps it to the screen.
    public static func openHeight(forSection id: String?) -> CGFloat {
        id.flatMap { openHeights[$0] } ?? defaultOpenHeight
    }
}
