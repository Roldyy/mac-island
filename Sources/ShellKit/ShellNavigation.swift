import Observation

/// Which group and sub-section the open island shows. Shared so the command bar can jump to a tab.
@MainActor @Observable
public final class ShellNavigation {
    public var selectedGroup: String
    public var sections: [String: String] = [:]

    public init(selectedGroup: String = ShellLayout.groups[0].id) { self.selectedGroup = selectedGroup }

    /// Jumps to the group and section holding `tabID`. Returns false for a tab outside the four groups.
    @discardableResult
    public func select(tabID: String) -> Bool {
        guard let group = ShellLayout.group(containing: tabID) else { return false }
        selectedGroup = group.id
        sections[group.id] = tabID
        return true
    }
}
