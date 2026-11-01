import AppKit
import IslandKit
import SwiftUI

public enum FansFeature {
    /// Created on first use only, so building the tab list opens neither the SMC nor XPC.
    @MainActor static let shared = FansModel.live()
    @MainActor private static var terminationObserver: NSObjectProtocol?

    /// True while the helper holds the fans in manual mode for this app, so the shell can show an
    /// indicator when the island is closed. Reads the `@Observable` model: a SwiftUI view that
    /// reads it in `body` is updated when it changes.
    @MainActor public static var isManualActive: Bool { shared.manualActive }

    /// The door the ported fan policy (PortKit's `FanControlBackend`) drives the helper through. The model is the
    /// same one the Ventilos tab shows, created on first use only.
    @MainActor public static var driver: any FanDriving { shared }

    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "fans", title: "Ventilos", systemImage: "fan") {
            AnyView(FansView(model: shared))
        }
    }

    /// Idempotent. Connects to the helper only if the user already approved it, and arranges for
    /// automatic mode to be sent when the app quits. Never registers the helper.
    @MainActor public static func start() {
        shared.start()
        guard terminationObserver == nil else { return }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { shared.stop() }
        }
    }

    /// Idempotent. Sends automatic to the helper if it is connected, then disconnects.
    @MainActor public static func stop() { shared.stop() }
}
