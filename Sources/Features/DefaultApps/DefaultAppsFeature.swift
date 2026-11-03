import IslandKit
import SwiftUI

/// Default apps: pick the app that opens a kind of file today (TextEdit, say), pick another one (Sublime Text), see
/// exactly what will change, apply it, undo it, and optionally keep the choice when macOS resets it.
///
/// Off by default. `start()` allows the feature (nothing is scanned, nothing is written); a scan and every write is a
/// click, and `stop()` (switch off, kill switch, safe mode) forgets what is on screen and unplugs the guard.
/// The registry descriptor lives in `ShellDescriptors` (id and tab id `defaultapps`), like the other modules' ones.
public enum DefaultAppsFeature {
    public static let id = "defaultapps"
    public static let pageID = "defaultapps"

    /// Created on first use only, so building the tab list creates nothing and reads no preference.
    @MainActor static let shared = DefaultAppsModel(environment: .live())

    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: id, title: "Apps par défaut", systemImage: "app.badge.checkmark") {
            AnyView(DefaultAppsTabView(model: shared))
        }
    }

    /// The body of the Settings page `defaultapps`.
    @MainActor public static func settingsBody() -> AnyView {
        AnyView(DefaultAppsPanel(model: shared))
    }

    /// Allows the feature. Scans nothing, writes nothing, never prompts. Idempotent.
    @MainActor public static func start() { shared.start() }

    /// Forgets what is on screen and unplugs the guard. Idempotent.
    @MainActor public static func stop() { shared.stop() }
}
