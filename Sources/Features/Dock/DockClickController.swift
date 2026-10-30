import CoreGraphics
import Foundation

@MainActor
final class DockClickController {
    /// Runs `work` after `delay` seconds on the main actor; the returned closure cancels it.
    typealias Scheduler = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> () -> Void

    /// How long after the mouse-up the action runs: the Dock has handled the click by then.
    static let actDelay: TimeInterval = 0.1

    static let mainQueue: Scheduler = { delay, work in
        let item = DispatchWorkItem { MainActor.assumeIsolated { work() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return { item.cancel() }
    }

    private let options: () -> DockClickOptions
    private let resolver: DockItemResolving
    private let windows: AppWindowAccessing
    private let workspace: WorkspaceQuerying
    private let schedule: Scheduler

    init(options: @escaping () -> DockClickOptions, resolver: DockItemResolving,
         windows: AppWindowAccessing, workspace: WorkspaceQuerying,
         schedule: Scheduler? = nil) {
        self.options = options
        self.resolver = resolver
        self.windows = windows
        self.workspace = workspace
        self.schedule = schedule ?? Self.mainQueue
    }

    private struct Pending {
        var app: DockApp
        var action: DockClickAction
        /// Set once the mouse-up scheduled the action.
        var cancel: (() -> Void)?
    }
    private var pending: Pending?

    /// Mouse down only decides: it captures which app was clicked and the state, before the Dock
    /// activates anything, so "frontmost" is still the old one. The action waits for the mouse-up, because
    /// the Dock handles the same click then and would undo a minimize or hide done earlier.
    @discardableResult
    func handleMouseDown(at point: CGPoint) -> DockClickAction {
        cancelPending()
        let options = options()
        guard options.anyEnabled, let app = resolver.app(at: point) else { return .none }
        let action = DockClickDecision.decide(DockClickInput(
            options: options, clickedBundleID: app.bundleID, frontmostBundleID: workspace.frontmostBundleID,
            windows: windows.windows(pid: app.pid), isHidden: workspace.isHidden(pid: app.pid)))
        if action != .none { pending = Pending(app: app, action: action, cancel: nil) }
        return action
    }

    /// Schedules the captured action about 100 ms after the release, unless the pointer is no longer
    /// on the icon that was pressed.
    func handleMouseUp(at point: CGPoint) {
        guard var p = pending, p.cancel == nil else { return }
        guard let under = resolver.app(at: point), under.bundleID == p.app.bundleID, under.pid == p.app.pid else {
            cancelPending(); return
        }
        p.cancel = schedule(Self.actDelay) { [weak self] in self?.fire() }
        pending = p
    }

    /// A drag, a stop or a new click: forget the captured action and cancel any scheduled one.
    func cancelPending() {
        pending?.cancel?()
        pending = nil
    }

    private func fire() {
        guard let p = pending else { return }
        pending = nil
        // Minimize, hide and cycle only make sense while the clicked app is still the frontmost one;
        // restore is the case where the Dock itself brings the app forward.
        if p.action != .restoreAll, workspace.frontmostBundleID != p.app.bundleID { return }
        windows.perform(p.action, pid: p.app.pid)
    }
}
