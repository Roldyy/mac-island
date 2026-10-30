import IslandKit
import SwiftUI

public enum DockFeature {
    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "dock", title: "Dock", systemImage: "dock.rectangle") {
            AnyView(Text("Dock (stub)").foregroundStyle(.white))
        }
    }
}
