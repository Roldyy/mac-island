import IslandKit
import SwiftUI

public enum FinderFeature {
    /// Created on first use only, so building the tab list touches nothing (no tap, no permission).
    @MainActor static let shared = FinderModel()

    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "finder", title: "Finder", systemImage: "folder") {
            AnyView(FinderTabView(model: shared))
        }
    }

    /// Install the key tap if the toggles and permissions allow it. Idempotent. Never prompts.
    @MainActor public static func start() { shared.start() }

    /// Remove the key tap and forget any pending cut. Idempotent.
    @MainActor public static func stop() { shared.stop() }
}
