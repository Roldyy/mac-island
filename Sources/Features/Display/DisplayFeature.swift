import IslandKit
import SwiftUI

public enum DisplayFeature {
    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "display", title: "Écran", systemImage: "sun.max") {
            AnyView(Text("Écran (stub)").foregroundStyle(.white))
        }
    }
}
