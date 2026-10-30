import IslandKit
import SwiftUI

public enum AgentsFeature {
    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "agents", title: "Agents", systemImage: "sparkles") {
            AnyView(AgentsTabView())
        }
    }

    /// Month tokens and cost for the closed island (the contract has no idle slot: the shell places this).
    @MainActor public static func idleView() -> AnyView {
        AnyView(AgentsIdleView())
    }
}
