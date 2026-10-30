import Foundation
import IslandKit
import SwiftUI

public enum ClipboardFeature {
    /// `~/Library/Application Support/be.roldy.macisland/Data`, where the migrator put the old data.
    static var dataDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("be.roldy.macisland", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
    }

    /// Created on first use only, so building the tab list touches nothing on disk.
    @MainActor static let shared = ClipboardModel(dataDirectory: dataDirectory)

    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "clipboard", title: "Presse-papiers", systemImage: "doc.on.clipboard") {
            AnyView(ClipboardView(model: shared))
        }
    }

    /// Start the pasteboard watcher and the plain-paste hotkey. Idempotent.
    @MainActor public static func start() { shared.start() }
}
