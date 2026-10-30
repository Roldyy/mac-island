import AppKit
import ApplicationServices

/// Finds the Dock item under the pointer through the Dock's own accessibility tree.
/// Reads only the app URL (bundle id) and the icon frame; no titles.
@MainActor
final class AXDockItemResolver: DockItemResolving {
    private var dockElement: AXUIElement?
    private var dockPID: pid_t = 0

    private func dock() -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: DockClickDecision.dockBundleID).first
        else { return nil }
        if dockElement == nil || dockPID != app.processIdentifier {
            let e = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(e, 0.15) // a stuck Dock must not freeze the island
            dockElement = e
            dockPID = app.processIdentifier
        }
        return dockElement
    }

    func app(at point: CGPoint) -> DockApp? {
        guard AXIsProcessTrusted(), let dock = dock(), let primary = NSScreen.screens.first else { return nil }
        let h = primary.frame.height
        let p = CoordinateFlip.ax(fromCocoa: point, primaryHeight: h)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(dock, Float(p.x), Float(p.y), &hit) == .success, let hit,
              AX.string(hit, kAXSubroleAttribute as String) == "AXApplicationDockItem",
              let url = AX.url(hit), let bundleID = Bundle(url: url)?.bundleIdentifier,
              let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
              let frame = AX.frame(hit)
        else { return nil }
        return DockApp(bundleID: bundleID, pid: running.processIdentifier,
                       iconFrame: CoordinateFlip.cocoa(fromAX: frame, primaryHeight: h))
    }
}
