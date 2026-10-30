import IslandKit
import SwiftUI

public enum TerminalFeature {
    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "terminal", title: "Terminal", systemImage: "terminal") {
            AnyView(Text("Terminal (stub)").foregroundStyle(.white))
        }
    }
}
