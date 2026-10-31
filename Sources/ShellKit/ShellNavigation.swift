import Observation

/// Where the open island is: the Spacieuse home, the Explorer grid, or one feature's panel.
public enum IslandRoute: Equatable, Sendable {
    case home
    case explore
    /// A feature tab id (also a feature id).
    case page(String)
}

/// Which page, group and sub-section the open island shows. Shared so the command bar can jump to a tab.
@MainActor @Observable
public final class ShellNavigation {
    public var route: IslandRoute = .home
    public var selectedGroup: String
    public var sections: [String: String] = [:]

    public init(selectedGroup: String = ShellLayout.groups[0].id) { self.selectedGroup = selectedGroup }

    /// Opens a feature's panel, keeping its group and sub-section in step. Works for any tab id.
    public func open(tabID: String) {
        if let group = ShellLayout.group(containing: tabID) {
            selectedGroup = group.id
            sections[group.id] = tabID
        }
        route = .page(tabID)
    }

    /// Jumps to the group and section holding `tabID`. Returns false for a tab outside the four groups.
    @discardableResult
    public func select(tabID: String) -> Bool {
        guard ShellLayout.group(containing: tabID) != nil else { return false }
        open(tabID: tabID)
        return true
    }

    public func goHome() { route = .home }

    /// The Explorer button toggles the grid.
    public func toggleExplore() { route = route == .explore ? .home : .explore }

    /// Escape and the back chevron: a page goes back to the home, the grid too, the home stays.
    @discardableResult
    public func back() -> Bool {
        guard route != .home else { return false }
        route = .home
        return true
    }
}
