import CoreGraphics
import Foundation

@MainActor
final class DockPreviewController {
    struct Screen { var frame: CGRect; var visibleFrame: CGRect }

    private let settings: () -> DockSettings
    private let resolver: DockItemResolving
    private let windows: AppWindowAccessing
    private let capturer: WindowCapturing
    private let permissions: DockPermissionChecking
    private let presenter: PreviewPresenting
    private let screens: () -> [Screen]
    private let clock: () -> TimeInterval
    let model: PreviewModel

    private var machine = PreviewStateMachine(delay: 0.4, grace: 0.3)
    private var throttle = CaptureThrottle(minInterval: 0.5)
    private var pointer = CGPoint.zero
    private var hovered: DockApp?
    private var shown: DockApp?
    private var captureTask: Task<Void, Never>?
    /// True while the state machine needs ticks (not idle): the coordinator runs its timer only then.
    var onNeedsTicks: ((Bool) -> Void)?
    private var needsTicks = false

    init(settings: @escaping () -> DockSettings, resolver: DockItemResolving, windows: AppWindowAccessing,
         capturer: WindowCapturing, permissions: DockPermissionChecking, presenter: PreviewPresenting,
         model: PreviewModel, screens: @escaping () -> [Screen], clock: @escaping () -> TimeInterval) {
        self.settings = settings
        self.resolver = resolver
        self.windows = windows
        self.capturer = capturer
        self.permissions = permissions
        self.presenter = presenter
        self.model = model
        self.screens = screens
        self.clock = clock
        model.onRaise = { [weak self] index in self?.raise(index) }
        model.onRequestScreenRecording = { [weak self] in self?.permissions.requestScreenRecording() }
    }

    func pointerMoved(_ p: CGPoint) {
        pointer = p
        let s = settings()
        guard s.previewEnabled else { cancel(); return }
        machine.delay = s.previewDelay
        hovered = nil
        let overPanel = presenter.panelFrame?.contains(p) ?? false
        // Accessibility is only asked while the pointer is inside the Dock strip.
        if !overPanel, screens().contains(where: { DockGeometry.band(screenFrame: $0.frame, visibleFrame: $0.visibleFrame)?.contains(p) == true }) {
            hovered = resolver.app(at: p)
        }
        step()
    }

    func tick() {
        guard settings().previewEnabled else { cancel(); return }
        step()
    }

    /// A click anywhere closes the preview (the click behaviour may be about to act on the same app).
    func pointerDown() { cancel() }

    func cancel() {
        hovered = nil
        apply(machine.cancel())
        updateTicks()
    }

    private func step() {
        let overPanel = presenter.panelFrame?.contains(pointer) ?? false
        apply(machine.update(hoveredIcon: hovered?.bundleID, overPanel: overPanel, now: clock()))
        updateTicks()
    }

    private func updateTicks() {
        let need = !machine.isIdle
        if need != needsTicks { needsTicks = need; onNeedsTicks?(need) }
    }

    private func apply(_ command: PreviewStateMachine.Command) {
        switch command {
        case .none: break
        case let .show(id):
            if let app = hovered, app.bundleID == id { present(app) }
        case .hide: dismiss()
        }
    }

    private func present(_ app: DockApp) {
        let list = windows.windows(pid: app.pid)
        let capped = ThumbnailLimits.cap(list)
        guard !capped.isEmpty else { dismiss(); return }
        captureTask?.cancel()
        let granted = permissions.screenRecordingGranted
        model.appName = app.bundleID.split(separator: ".").last.map(String.init) ?? ""
        model.items = capped.enumerated().map { PreviewItem(id: $0.offset, title: $0.element.title, thumbnail: nil, isMinimized: $0.element.isMinimized) }
        model.needsScreenRecording = !granted
        shown = app
        reposition()
        guard granted, throttle.shouldCapture(key: app.pid, now: clock()) else { return }
        let frames = capped.map(\.frame)
        let capturer = capturer
        let pid = app.pid
        captureTask = Task { [weak self] in
            let images = await capturer.thumbnails(pid: pid, frames: frames, maxSize: ThumbnailLimits.maxSize)
            guard !Task.isCancelled, let self, self.shown?.pid == pid else { return }
            for (i, image) in images.enumerated() where self.model.items.indices.contains(i) {
                self.model.items[i].thumbnail = image
            }
            self.reposition()
        }
    }

    private func reposition() {
        guard let app = shown else { return }
        let all = screens()
        let screen = all.first(where: { $0.frame.intersects(app.iconFrame) }) ?? all.first
        guard let screen, let edge = DockGeometry.edge(screenFrame: screen.frame, visibleFrame: screen.visibleFrame) else { return }
        presenter.show(near: app.iconFrame, edge: edge, screenFrame: screen.frame)
    }

    private func dismiss() {
        captureTask?.cancel()
        captureTask = nil
        shown = nil
        presenter.hide()
        model.clear() // releases the images
    }

    private func raise(_ index: Int) {
        guard let app = shown else { return }
        windows.raise(pid: app.pid, windowAt: index)
        dismiss()
        _ = machine.cancel()
        updateTicks()
    }
}
