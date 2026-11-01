import Foundation
import IslandKit
import PortKit
import SwiftUI

/// The island's "Étagère" tab. The shelf itself is the ported Vorssaint one (`PortKit/Bridge/Shelf.swift`): this
/// target keeps the tab id `shelf` (the Home tile, the Settings page and the migrated switch all point at it), the
/// Downloads segment (ours until wave 8), and hosts the ported items in the first segment. The registry starts and
/// stops the shelf through `PortFeatureBinding`, not through this type.
public enum ShelfFeature {
    /// Created on first use only, so building the tab list touches nothing.
    @MainActor static let shared = ShelfModel()

    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "shelf", title: "Étagère", systemImage: "tray.and.arrow.down") {
            AnyView(ShelfView(model: shared))
        }
    }

    /// Starts the ported shelf the way the registry does (the same binding, so the one-time import of the old store
    /// applies), then the Downloads watcher. Idempotent. The app delegate's `"shelf"` starter calls it and wins over
    /// the binding's own entry in the merged starters, so it must reach the binding: otherwise the ported shelf would
    /// never start. Only the registry calls it, after it decided the feature may run.
    @MainActor public static func start() {
        PortFeatureBinding.shared.starters["shelf"]?()
        shared.start()
    }
}
