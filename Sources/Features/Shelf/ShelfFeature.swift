import Foundation
import IslandKit
import SwiftUI

public enum ShelfFeature {
    /// `~/Library/Application Support/be.roldy.macisland/Data`.
    static var dataDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("be.roldy.macisland", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
    }

    /// Created on first use only, so building the tab list touches nothing on disk.
    @MainActor static let shared = ShelfModel(dataDirectory: dataDirectory)

    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "shelf", title: "Étagère", systemImage: "tray.and.arrow.down") {
            AnyView(ShelfView(model: shared))
        }
    }

    /// Load the shelf and start the Downloads watcher. Idempotent; optional (the tab view also
    /// starts it when first shown), call it at launch to have downloads ready before the first open.
    @MainActor public static func start() { shared.start() }
}
