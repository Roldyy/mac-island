import IslandKit
import SwiftUI

public enum TerminalFeature {
    public static let pageID = "terminal"

    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "terminal", title: "Terminal", systemImage: "terminal") {
            AnyView(TerminalTabView())
        }
    }

    /// Shared status source for the island wings. Pair with `ClaudeStatusPill(model:)`.
    @MainActor public static func claudeStatus() -> ClaudeStatusModel { sharedStatus }

    /// The body of the Settings page `terminal`: the colour profile card. Creating it starts no shell.
    @MainActor public static func settingsBody() -> AnyView {
        AnyView(TerminalSettingsBody(model: profilesModel))
    }

    @MainActor private static let sharedStatus = ClaudeStatusModel()

    @MainActor private static let profilesModel = TerminalProfilesModel(
        store: TerminalProfileStore.standard(), session: TerminalSession.shared)
}
