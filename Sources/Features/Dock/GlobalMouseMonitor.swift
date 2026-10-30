import AppKit

/// Global (other apps) mouse-down and mouse-moved monitors plus a local moved monitor (pointer over our own panel).
/// Monitoring only, no event tap: clicks always reach their target.
@MainActor
final class GlobalMouseMonitor: MouseEventSource {
    private var tokens: [Any] = []
    var isRunning: Bool { !tokens.isEmpty }

    func start(_ handler: @escaping (MouseEvent) -> Void) {
        guard !isRunning else { return }
        let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
            MainActor.assumeIsolated { handler(.down(NSEvent.mouseLocation)) }
        }
        let moved = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { _ in
            MainActor.assumeIsolated { handler(.moved(NSEvent.mouseLocation)) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
            MainActor.assumeIsolated { handler(.moved(NSEvent.mouseLocation)) }
            return event
        }
        tokens = [down, moved, local].compactMap { $0 }
    }

    func stop() {
        tokens.forEach { NSEvent.removeMonitor($0) }
        tokens = []
    }
}
