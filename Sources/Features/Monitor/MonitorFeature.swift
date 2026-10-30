import IslandKit
import SwiftUI

public enum MonitorFeature {
    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "monitor", title: "Moniteur", systemImage: "gauge.with.dots.needle.bottom.50percent") {
            AnyView(Text("Moniteur (stub)").foregroundStyle(.white))
        }
    }
}
