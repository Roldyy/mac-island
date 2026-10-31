import AppKit
import Foundation
import IslandKit
import IslandTestSupport
import SwiftUI
import Testing
@testable import ShellKit

/// Renders pages to PNG files in the temp directory so a person can look at them.
/// The assertion is only that a non-empty image came out.
@MainActor
@Suite struct SettingsRenderTests {
    @Test func rendersFourPages() throws {
        let b = TestDefaults.make(); defer { b.cleanup() }
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-render-marker-\(UUID().uuidString)"))
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all, defaults: b.defaults, crashMarker: marker)
        let env = SettingsEnvironment(
            registry: registry, defaults: b.defaults, sheetTabs: [:], openPermission: { _ in }, relaunch: nil,
            login: LoginItemModel(defaults: b.defaults),
            backup: SettingsBackup(defaults: b.defaults, domain: "render", directory: URL(fileURLWithPath: NSTemporaryDirectory())))
        let dir = ProcessInfo.processInfo.environment["MIS_RENDER_DIR"] ?? NSTemporaryDirectory()
        for id in ["general", "keepawake", "radial", "advanced", "dockclicks"] {
            let view = HStack(spacing: 0) {
                SettingsSidebar(router: SettingsRouter(defaults: b.defaults)).frame(width: 230)
                SettingsPageView(pageID: id, env: env)
            }
            .frame(width: 900, height: 700)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark)
            // ImageRenderer cannot draw AppKit-backed controls (List, ScrollView, TextField): host the view instead.
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("settings-\(id).png"))
            #expect(png.count > 5_000)
        }
    }
}
