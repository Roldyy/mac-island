import IslandKit
import SwiftUI

public enum AudioFeature {
    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "audio", title: "Mixer", systemImage: "slider.vertical.3") {
            AnyView(Text("Mixer (stub)").foregroundStyle(.white))
        }
    }
}
