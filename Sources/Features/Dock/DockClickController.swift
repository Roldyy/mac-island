import CoreGraphics

@MainActor
final class DockClickController {
    private let options: () -> DockClickOptions
    private let resolver: DockItemResolving
    private let windows: AppWindowAccessing
    private let workspace: WorkspaceQuerying

    init(options: @escaping () -> DockClickOptions, resolver: DockItemResolving,
         windows: AppWindowAccessing, workspace: WorkspaceQuerying) {
        self.options = options
        self.resolver = resolver
        self.windows = windows
        self.workspace = workspace
    }

    /// Runs on mouse down, before the Dock activates the app, so "frontmost" is still the old state.
    @discardableResult
    func handleMouseDown(at point: CGPoint) -> DockClickAction {
        let options = options()
        guard options.anyEnabled, let app = resolver.app(at: point) else { return .none }
        let action = DockClickDecision.decide(DockClickInput(
            options: options, clickedBundleID: app.bundleID, frontmostBundleID: workspace.frontmostBundleID,
            windows: windows.windows(pid: app.pid), isHidden: workspace.isHidden(pid: app.pid)))
        if action != .none { windows.perform(action, pid: app.pid) }
        return action
    }
}
