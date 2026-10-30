import IslandKit
import SwiftUI

public enum DisplayFeature {
    /// Created on first use only, so building the tab list touches no display and no process.
    @MainActor static let brightness: BrightnessModel = {
        var settings = DisplaySettings()
        return BrightnessModel(backend: DisplayServicesBackend(),
                               controlEnabled: settings.brightnessControlEnabled,
                               persistEnabled: { settings.brightnessControlEnabled = $0 })
    }()
    @MainActor static let autoQuit = AutoQuitModel()

    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "display", title: "Écran", systemImage: "sun.max") {
            AnyView(DisplayView(brightness: brightness, autoQuit: autoQuit))
        }
    }

    /// Start the auto-quit scan loop. Idempotent.
    @MainActor public static func start() {
        brightness.refresh()
        autoQuit.start()
    }

    /// Stop the scan loop. Idempotent.
    @MainActor public static func stop() { autoQuit.stop() }
}
