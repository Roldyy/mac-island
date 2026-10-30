import AppKit
import IslandKit
import SwiftUI

public enum DockFeature {
    @MainActor private static var coordinator: DockCoordinator?
    @MainActor private static let permissions = SystemPermissions()

    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "dock", title: "Dock", systemImage: "dock.rectangle") {
            AnyView(DockTabView(settings: DockSettings(), permissions: permissions))
        }
    }

    /// Starts the global mouse monitors. Idempotent. Settings are read live, so toggling in the tab needs no restart.
    @MainActor public static func start() {
        if coordinator == nil { coordinator = makeCoordinator() }
        coordinator?.start()
    }

    /// Removes the monitors and closes any preview. Idempotent.
    @MainActor public static func stop() { coordinator?.stop() }

    @MainActor private static func makeCoordinator() -> DockCoordinator {
        let settings: () -> DockSettings = { DockSettings() }
        let resolver = AXDockItemResolver()
        let windows = AXAppWindows()
        let model = PreviewModel()
        let click = DockClickController(options: { settings().clickOptions }, resolver: resolver,
                                        windows: windows, workspace: SystemWorkspace())
        let preview = DockPreviewController(
            settings: settings, resolver: resolver, windows: windows, capturer: SCKWindowCapturer(),
            permissions: permissions, presenter: PreviewPanelPresenter(model: model), model: model,
            screens: { NSScreen.screens.map { .init(frame: $0.frame, visibleFrame: $0.visibleFrame) } },
            clock: { ProcessInfo.processInfo.systemUptime })
        return DockCoordinator(source: GlobalMouseMonitor(), click: click, preview: preview)
    }
}
