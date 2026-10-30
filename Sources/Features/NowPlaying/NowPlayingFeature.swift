import IslandKit
import SwiftUI

public enum NowPlayingFeature {
    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "nowplaying", title: "Lecture", systemImage: "play.circle") {
            AnyView(Text("Lecture (stub)").foregroundStyle(.white))
        }
    }
}
