import IslandKit
import SwiftUI

public enum ShelfFeature {
    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "shelf", title: "Étagère", systemImage: "tray.and.arrow.down") {
            AnyView(Text("Étagère (stub)").foregroundStyle(.white))
        }
    }
}
