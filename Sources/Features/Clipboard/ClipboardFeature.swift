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

    /// Lent by the app delegate (this target cannot see the island or the navigation): opens the island on the
    /// Presse-papiers tab. The history shortcut and a click on the menu bar preview both end here.
    @MainActor public static var openHistory: @MainActor () -> Void = {}

    /// The text the menu bar item shows next to its icon (nil: none). The model publishes it; the app delegate lends
    /// the menu bar item through `onMenuBarPreviewChange`, which is called at once with the current value, so a
    /// preview published before the item existed is not lost.
    @MainActor public private(set) static var menuBarPreview: String?
    @MainActor public static var onMenuBarPreviewChange: @MainActor (String?) -> Void = { _ in } {
        didSet { onMenuBarPreviewChange(menuBarPreview) }
    }
    @MainActor static func publishMenuBarPreview(_ text: String?) {
        guard text != menuBarPreview else { return }
        menuBarPreview = text
        onMenuBarPreviewChange(text)
    }

    /// The Settings rows of the history and plain-paste pages (the app delegate registers them in `SettingsActions`).
    @MainActor public static var pinnedCount: Int { shared.pinnedCount }
    @MainActor public static var recentCount: Int { shared.recentCount }
    /// One line for the Settings page: "Collage sans style actif : ⌥⌘V", or why the shortcut does not work
    /// ("Raccourci déjà utilisé par une autre app ...", "autorisation Accessibilité requise").
    @MainActor public static var plainPasteStatus: String { shared.plainPasteStatus }
    /// "Effacer non épinglés": the pinned items stay. The page asks for the confirmation.
    @MainActor public static func clearUnpinned() { shared.clearUnpinned() }

    /// Pastes the clipboard as plain text, the way the plain-paste shortcut does (the island's extra dock calls it).
    @MainActor public static func pastePlain() { shared.plainPasteTriggered() }

    /// Start the pasteboard watcher and the plain-paste hotkey. Idempotent.
    @MainActor public static func start() { shared.start() }

    /// Stops monitoring: the pasteboard watcher, a pending auto-clear and the plain-paste hotkey. What is already
    /// in the history stays on disk and in the tab. The next `start()` arms everything again and records only what is
    /// copied from then on.
    @MainActor public static func stop() { shared.stop() }
}
