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

    /// Posted by the registry's stopper (PortKit `ClipboardLane`, which cannot import this target): switch off, kill
    /// switch, safe mode or quarantine. A started model stops monitoring. The same string is in
    /// `Sources/PortKit/Bridge/Clipboard.swift`; a PortKit test reads both files and fails when they differ.
    public static let stopRequested = Notification.Name("be.roldy.macisland.clipboard.stop")

    /// Lent by the app delegate (this target cannot see PortKit or the registry): true while the ported Scratchpad
    /// feature is bound and running. It writes the same `Scratchpad.json`, so the Bloc-notes pane is then read-only.
    @MainActor public static var portedScratchpadRunning: @MainActor () -> Bool = { false }

    /// Start the pasteboard watcher and the plain-paste hotkey. Idempotent.
    @MainActor public static func start() { shared.start() }

    /// Stops monitoring: the pasteboard watcher, a pending auto-clear and the plain-paste hotkey. What is already
    /// in the history stays on disk and in the tab. The next `start()` arms everything again and records only what is
    /// copied from then on.
    @MainActor public static func stop() { shared.stop() }
}
