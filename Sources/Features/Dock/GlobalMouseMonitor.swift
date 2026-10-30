import AppKit

/// Global (other apps) mouse down / up / drag / moved monitors plus a local moved monitor (pointer over our own panel).
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
        let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            MainActor.assumeIsolated { handler(.up(NSEvent.mouseLocation)) }
        }
        let dragged = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { _ in
            MainActor.assumeIsolated { handler(.dragged(NSEvent.mouseLocation)) }
        }
        let moved = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { _ in
            MainActor.assumeIsolated { handler(.moved(NSEvent.mouseLocation)) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
            MainActor.assumeIsolated { handler(.moved(NSEvent.mouseLocation)) }
            return event
        }
        tokens = [down, up, dragged, moved, local].compactMap { $0 }
    }

    func stop() {
        tokens.forEach { NSEvent.removeMonitor($0) }
        tokens = []
    }
}
