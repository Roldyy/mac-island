import IslandKit
import SwiftUI

public enum ClipboardFeature {
    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "clipboard", title: "Presse-papiers", systemImage: "doc.on.clipboard") {
            AnyView(Text("Clipboard (stub)").foregroundStyle(.white))
        }
    }
}
