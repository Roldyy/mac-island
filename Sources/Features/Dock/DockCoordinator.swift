import Foundation

/// Wires the mouse source to the click and preview controllers. `start()` / `stop()` are idempotent.
@MainActor
final class DockCoordinator {
    private let source: MouseEventSource
    private let click: DockClickController?
    private let preview: DockPreviewController?
    private var timer: Timer?
    private(set) var isStarted = false

    init(source: MouseEventSource, click: DockClickController?, preview: DockPreviewController?) {
        self.source = source
        self.click = click
        self.preview = preview
        preview?.onNeedsTicks = { [weak self] need in need ? self?.startTimer() : self?.stopTimer() }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        source.start { [weak self] event in
            guard let self else { return }
            switch event {
            case let .down(p):
                // Decide on the click first: it needs the state before the Dock activates the app.
                self.preview?.pointerDown()
                self.click?.handleMouseDown(at: p)
            case let .moved(p):
                self.preview?.pointerMoved(p)
            }
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        source.stop()
        preview?.cancel()
        stopTimer()
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.preview?.tick() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
