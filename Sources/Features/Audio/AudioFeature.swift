import IslandKit
import SwiftUI

public enum AudioFeature {
    /// Created on first use only, so building the tab list touches no audio hardware.
    @MainActor static let shared = AudioFeatureModel.live()

    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "audio", title: "Mixer", systemImage: "slider.vertical.3") {
            AnyView(AudioView(model: shared))
        }
    }

    /// Start the device-priority listener. Idempotent. Never prompts for any permission.
    @MainActor public static func start() { shared.start() }

    /// Release every tap and listener. Idempotent. Also runs on app termination once started.
    @MainActor public static func stop() { shared.stop() }
}
