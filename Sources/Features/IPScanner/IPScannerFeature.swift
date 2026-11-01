import IslandKit
import SwiftUI

/// The IP scanner: a "Réseau local" tab in the island and a "Scanner IP" page in Settings, both on one model.
///
/// Off by default. `start()` only allows the feature (nothing is read, nothing is sent); every network action is a
/// button the user clicks, and `stop()` (switch off, kill switch, safe mode) cancels it all and forgets the results.
/// The registry descriptor lives in `ShellDescriptors` (id and tab id `ipscanner`), like the other modules' ones.
public enum IPScannerFeature {
    public static let id = "ipscanner"
    public static let pageID = "ipscanner"

    /// Created on first use only, so building the tab list creates nothing and reads no preference.
    @MainActor static let shared = IPScannerModel(settings: IPScannerSettings(defaults: AppDefaults.make() ?? .standard))

    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: id, title: "Réseau local", systemImage: "dot.radiowaves.left.and.right") {
            AnyView(IPScannerTabView(model: shared))
        }
    }

    /// The body of the Settings page `ipscanner`.
    @MainActor public static func settingsBody() -> AnyView {
        AnyView(IPScannerSettingsBody(model: shared))
    }

    /// Allows the feature. Sends nothing, never prompts. Idempotent.
    @MainActor public static func start() { shared.start() }

    /// Cancels any scan, drops the results. Idempotent.
    @MainActor public static func stop() { shared.stop() }
}
