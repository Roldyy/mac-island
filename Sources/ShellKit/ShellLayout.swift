import Foundation

/// One sub-view of a group, backed by an existing feature tab.
public struct ShellSection: Identifiable, Equatable, Sendable {
    /// Tab id of the feature module; also its feature id.
    public let id: String
    public let title: String
}

/// One of the four fixed island tabs.
public struct ShellGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let sections: [ShellSection]
}

/// The island's four daily tabs. Pure data plus lookups, so the layout is testable without a view.
public enum ShellLayout {
    public static let groups: [ShellGroup] = [
        ShellGroup(id: "terminal", title: "Terminal", systemImage: "terminal", sections: [
            ShellSection(id: "terminal", title: "Terminal"), ShellSection(id: "agents", title: "Claude"),
        ]),
        ShellGroup(id: "clipboard", title: "Presse-papiers", systemImage: "doc.on.clipboard", sections: [
            ShellSection(id: "clipboard", title: "Presse-papiers"), ShellSection(id: "shelf", title: "Étagère"),
        ]),
        ShellGroup(id: "media", title: "Lecture", systemImage: "play.circle", sections: [
            ShellSection(id: "nowplaying", title: "Lecture"), ShellSection(id: "audio", title: "Mixer"),
            ShellSection(id: "keepawake", title: "Éveil"),
        ]),
        ShellGroup(id: "monitor", title: "Moniteur", systemImage: "gauge.with.dots.needle.bottom.50percent", sections: [
            ShellSection(id: "monitor", title: "Moniteur"), ShellSection(id: "fans", title: "Ventilos"),
        ]),
    ]

    public static func group(containing tabID: String) -> ShellGroup? {
        groups.first { $0.sections.contains { $0.id == tabID } }
    }

    /// Feature tabs that live in no group (reached from the Settings window instead).
    public static func tabsOutsideGroups(_ tabIDs: [String]) -> [String] {
        tabIDs.filter { group(containing: $0) == nil }
    }

    public static func visibleSections(of group: ShellGroup, isEnabled: (String) -> Bool) -> [ShellSection] {
        group.sections.filter { isEnabled($0.id) }
    }

    /// The remembered section when it is still visible, otherwise the first visible one.
    public static func resolvedSection(remembered: String?, visible: [ShellSection]) -> String? {
        if let remembered, visible.contains(where: { $0.id == remembered }) { return remembered }
        return visible.first?.id
    }

    // MARK: - Explorer

    /// Tabs the Explorer grid lists: the grouped ones first in island order, then the rest, enabled only.
    public static func exploreTabIDs(available: [String], isEnabled: (String) -> Bool) -> [String] {
        let grouped = groups.flatMap { $0.sections.map(\.id) }.filter(available.contains)
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
