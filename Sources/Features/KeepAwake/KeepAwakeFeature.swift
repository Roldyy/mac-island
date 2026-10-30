import IslandKit
import SwiftUI

public enum KeepAwakeFeature {
    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "keepawake", title: "Éveil", systemImage: "cup.and.saucer") {
            AnyView(Text("Éveil (stub)").foregroundStyle(.white))
        }
    }
}
