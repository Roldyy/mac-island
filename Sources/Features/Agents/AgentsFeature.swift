import IslandKit
import SwiftUI

public enum AgentsFeature {
    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "agents", title: "Agents", systemImage: "sparkles") {
            AnyView(Text("Agents (stub)").foregroundStyle(.white))
        }
    }
}
