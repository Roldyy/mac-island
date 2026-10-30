import IslandKit
import SwiftUI

public enum FinderFeature {
    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "finder", title: "Finder", systemImage: "folder") {
            AnyView(Text("Finder (stub)").foregroundStyle(.white))
        }
    }
}
