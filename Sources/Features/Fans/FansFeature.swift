import IslandKit
import SwiftUI

public enum FansFeature {
    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "fans", title: "Ventilos", systemImage: "fan") {
            AnyView(Text("Ventilos (stub)").foregroundStyle(.white))
        }
    }
}
