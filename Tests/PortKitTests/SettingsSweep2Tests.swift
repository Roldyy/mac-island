import AppKit
import Foundation
import IslandKit
import IslandTestSupport
import SwiftUI
import Testing
@testable import PortKit
@testable import ShellKit

/// Sweep 2 (pages 35-67 of the reference app): renders every page the way the Settings window does, with every lane
/// bound, writes one PNG per page into `MIS_SWEEP_DIR` (default: the temp directory). `scripts/port/SWEEP-2.md` is built
/// from OCR of those images against the crawled ground truth. The assertions are the contract that survived the sweep: no page shows "Bientôt", nothing is clipped.
@MainActor
@Suite(.serialized) struct SettingsSweep2Tests {
    static let pageIDs = [
        "scrollreverse", "hscroll", "middleclick", "focusfollows", "smoothscroll", "linearscroll", "noaccel",
        "sidebuttons", "mouseshortcuts", "clickfilter", "quitprotect", "debounce", "superkey", "snippets",
        "cutpaste", "renameshortcut", "shelf", "media", "urlcleaner", "appupdates", "cleaner", "homebrew",
        "uninstaller", "forcequit", "ports", "shortcuts", "kbdlight", "advanced", "about", "whatsnew", "support",
    ]

    /// In-page switches that hide the rest of their page while off.
    static let pageSwitches = [
        DefaultsKey.shelfEnabled, DefaultsKey.finderCutPasteEnabled, DefaultsKey.finderRenameEnabled,
        DefaultsKey.urlCleanerEnabled, DefaultsKey.superKeyEnabled,
    ]

    static var outputDirectory: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["MIS_SWEEP_DIR"] ?? NSTemporaryDirectory())
    }

    struct Rendered { var png: Data; var content: CGFloat }

    func registry(_ defaults: UserDefaults, binding: PortFeatureBinding) -> FeatureRegistry {
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-sweep2-marker-\(UUID().uuidString)"))
        return FeatureRegistry(descriptors: ShellDescriptors.all + binding.descriptors, defaults: defaults,
                               crashMarker: marker, withdraw: { _ in })
    }

    func wire(_ registry: FeatureRegistry, binding: PortFeatureBinding) {
        SettingsPageBodies.removeAll()
        for id in PortBridge.registeredPageIDs {
            SettingsPageBodies.register(pageID: id) { PortBridge.settingsBody(pageID: id) ?? AnyView(EmptyView()) }
        }
        for page in binding.pages {
            SettingsPageBodies.register(pageID: page.pageID, featureID: page.featureID, registry: registry,
                                        openPermission: { _ in }, page.body)
        }
    }

    func render(_ id: String, env: SettingsEnvironment, dark: Bool = true) throws -> Rendered {
        let height: CGFloat = 7000
        let view = SettingsPageView(pageID: id, env: env)
            .frame(width: 700, height: height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 700, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        // Where the drawn content ends (last row of pixels that is not the background), to cut the empty tail and to
        // tell a page that fits from one that runs off the 4200 pt frame.
        let content = Self.contentHeight(rep)
        let cropped = Self.crop(rep, toHeight: min(height, content + 24))
        let png = try #require(cropped.representation(using: .png, properties: [:]))
        return Rendered(png: png, content: content)
    }

    static func contentHeight(_ rep: NSBitmapImageRep) -> CGFloat {
        guard let background = rep.colorAt(x: 2, y: rep.pixelsHigh - 2) else { return CGFloat(rep.pixelsHigh) }
        var y = rep.pixelsHigh - 1
        while y > 0 {
            for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                if abs(c.redComponent - background.redComponent) + abs(c.greenComponent - background.greenComponent)
                    + abs(c.blueComponent - background.blueComponent) > 0.06 { return CGFloat(y) }
            }
            y -= 1
        }
        return 0
    }

    static func crop(_ rep: NSBitmapImageRep, toHeight h: CGFloat) -> NSBitmapImageRep {
        let width = rep.pixelsWide, height = Int(h)
        guard let cg = rep.cgImage, let part = cg.cropping(to: CGRect(x: 0, y: 0, width: width, height: height)) else { return rep }
        return NSBitmapImageRep(cgImage: part)
    }

    @Test func rendersEveryPageOfTheRange() throws {
        try PortHostFixture.isolated { defaults in
            let binding = PortFeatureBinding(permissions: { PortPermissionState() })
            PortLanes.bindAll(into: binding)
            let registry = registry(defaults, binding: binding)
            // The app registers upstream's defaults after the registry seed; the sweep draws the pages the same way,
            // with every feature installed and the in-page switches of the pages that hide their rows when off turned on
            // (the reference app was crawled in that state).
            Defaults.register(in: defaults)
            for descriptor in registry.descriptors { registry.setSwitch(descriptor.id, to: true) }
            for key in Self.pageSwitches { defaults.set(true, forKey: key) }
            PortHost.availability = { _ in true }  // "installed": the shortcuts list shows every feature (restored by the fixture)
            wire(registry, binding: binding)
            defer { SettingsPageBodies.removeAll() }
            let env = SettingsEnvironment(
                registry: registry, defaults: defaults, sheetTabs: [:], openPermission: { _ in }, relaunch: nil,
                login: LoginItemModel(defaults: defaults),
                backup: SettingsBackup(defaults: defaults, domain: "sweep2", directory: URL(fileURLWithPath: NSTemporaryDirectory())))
            let dir = Self.outputDirectory
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for id in Self.pageIDs {
                let page = try #require(SettingsPageCatalog.page(id))
                let rendered = try render(id, env: env)
                try rendered.png.write(to: dir.appendingPathComponent("sweep2-\(id).png"))
                #expect(rendered.png.count > 3_000, "\(id)")
                #expect(!page.isComingSoon, "\(id) reads Bientôt")
                let planned = SettingsPageModel.blocks(for: page).flatMap(\.rows).filter {
                    !$0.isLive && $0.item.kind != .caption && $0.item.kind != .heading
                }
                #expect(planned.isEmpty, "\(id) shows greyed rows: \(planned.map(\.item.label))")
                #expect(rendered.content < 6900, "\(id) runs off the rendered height: \(rendered.content)")
            }
        }
    }

    /// About with an update on offer: the rows that only exist then ("Télécharger la mise à jour", "Dernière recherche").
    @Test func aboutShowsTheUpdateRowsWhenOneIsAvailable() async throws {
        let bench = TestDefaults.make(); defer { bench.cleanup() }
        let body = #"[{"tag_name":"v9.0.0","html_url":"https://github.com/Roldyy/mac-island/releases/tag/v9.0.0","body":"Notes de la 9.0"}]"#
        let checker = UpdateChecker(fetch: { _ in Data(body.utf8) }, currentVersion: { "1.0.0" })
        await checker.check(defaults: bench.defaults)
        let page = try #require(SettingsPageCatalog.page("about"))
        let view = AboutPage(page: page, defaults: bench.defaults, checker: checker)
            .frame(width: 700, height: 1900).background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 1900)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let cropped = Self.crop(rep, toHeight: min(1900, Self.contentHeight(rep) + 24))
        let png = try #require(cropped.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
        try png.write(to: Self.outputDirectory.appendingPathComponent("sweep2-about-update.png"))
        #expect(png.count > 3_000)
    }
}
