import AppKit
import IslandKit
import SwiftUI

public enum FansFeature {
    /// Created on first use only, so building the tab list opens neither the SMC nor XPC.
    @MainActor static let shared = FansModel.live()
    @MainActor private static var terminationObserver: NSObjectProtocol?

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
