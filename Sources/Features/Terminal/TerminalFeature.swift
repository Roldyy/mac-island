import IslandKit
import SwiftUI

public enum TerminalFeature {
    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "terminal", title: "Terminal", systemImage: "terminal") {
            AnyView(TerminalHostView())
        }
    }

    /// Shared status source for the island wings. Pair with `ClaudeStatusPill(model:)`.
    @MainActor public static func claudeStatus() -> ClaudeStatusModel { sharedStatus }

    @MainActor private static let sharedStatus = ClaudeStatusModel()
}
