import AppKit
import SwiftUI

/// The app's icon, loaded once per bundle id (not on every render).
struct AppIconView: View {
    let bundleID: String
    let pid: Int32
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: "app.dashed").resizable().foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
        .task(id: bundleID) {
            if let running = NSRunningApplication(processIdentifier: pid), let image = running.icon {
                icon = image
            } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                icon = NSWorkspace.shared.icon(forFile: url.path)
            }
        }
    }
}
