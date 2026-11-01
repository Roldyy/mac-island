import IslandKit
import SwiftUI

/// The "Écran" tab and its registry feature `display`: auto-quit of idle apps. Brightness (built-in, external over
/// DDC, keyboard light) is the ported feature `brightness` (`PortKit/Bridge/DisplayBrightness.swift`), with its
/// own switch and Settings pages; the key `brightnessControlEnabled` is the same one it reads.
public enum DisplayFeature {
    @MainActor static let autoQuit = AutoQuitModel()

    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "display", title: "Écran", systemImage: "sun.max") {
            AnyView(DisplayView(autoQuit: autoQuit))
        }
    }

    /// Start the auto-quit scan loop. Idempotent.
    @MainActor public static func start() {
        autoQuit.start()
    }

    /// Stop the scan loop. Idempotent.
    @MainActor public static func stop() { autoQuit.stop() }
}
