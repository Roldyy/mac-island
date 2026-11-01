import AppKit
import PortKit

MainActor.assumeIsolated {
    // The ported guards re-exec this binary with a --*-cleanup flag to undo a system change after the app
    // died. That process cleans up and exits here, before any NSApplication exists: it must never start a
    // second app (no island, no tap, no Dock icon).
    PortBridge.runCleanupFlagsIfRequested()

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)  // no Dock icon: the island is the interface
    app.run()
}
