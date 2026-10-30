import IslandKit
import SwiftUI

public enum CommandBarFeature {
    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "commandbar", title: "Commandes", systemImage: "command") {
            AnyView(Text("Commandes (stub)").foregroundStyle(.white))
        }
    }
}
