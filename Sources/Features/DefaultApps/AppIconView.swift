import AppKit
import SwiftUI

/// An app's icon from its bundle (the workspace's own icon, cached by path).
struct AppIconView: View {
    let url: URL
    var size: CGFloat = 22

    var body: some View {
        Image(nsImage: AppIconCache.icon(for: url))
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

@MainActor
enum AppIconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for url: URL) -> NSImage {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(icon, forKey: key)
        return icon
    }
}
