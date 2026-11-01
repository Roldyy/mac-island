import Foundation
import SwiftUI
import Testing
@testable import PortKit
@testable import ShellKit

/// The Settings sweep of lane G: after every lane has bound, which pages still show the "Bientôt" badge or greyed
/// planned rows. The list may only shrink: a page that lands here without being named below is a regression, a page a
/// lane wires is simply removed from `stillPending` in the same change.
@MainActor
@Suite(.serialized) struct SettingsSweepTests {
    /// Page id -> why it is not wired yet. One owner each.
    static let stillPending: [String: String] = [
        "monitor": "lane A/B: monitor samplers and alerts (W6A); the live alert rows stay",
        "fans": "lane A/B: fan curve UI over our helper (W6C)",
        "cutpaste": "lane C: Finder cut and paste (W7A)",
        "renameshortcut": "lane C: Finder rename shortcut (W7A)",
        "cleaner": "lane C: cleaner (W7B)",
        "appupdates": "lane D: app updates (W7C)",
        "homebrew": "lane D: Homebrew (W7C)",
        "uninstaller": "lane D: uninstaller (W7D)",
        "clipboard": "decision of W5A: our Clipboard module keeps the history; the ported history page writes keys it never reads",
        "pasteplain": "decision of W5A: our Clipboard module owns the plain-paste shortcut",
    ]

    private func wireEveryLane() -> (soon: [String], planned: [String]) {
        SettingsPageBodies.removeAll()
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        PortLanes.bindAll(into: binding)
        for page in binding.pages { SettingsPageBodies.register(pageID: page.pageID) { page.body() } }
        for id in PortBridge.registeredPageIDs { SettingsPageBodies.register(pageID: id) { AnyView(EmptyView()) } }
        // What the app delegate registers itself (it owns the HomeModel): the island editors.
        SettingsPageBodies.register(pageID: "island") { AnyView(EmptyView()) }

        func isPlanned(_ row: ShellKit.SettingsRow) -> Bool {
            !row.isLive && row.item.kind != .caption && row.item.kind != .heading
        }
        let soon = SettingsPageCatalog.all.filter(\.isComingSoon).map(\.id)
        let planned = SettingsPageCatalog.all.filter { page in
            page.kind == .declarative && SettingsPageModel.blocks(for: page).flatMap(\.rows).contains(where: isPlanned)
        }.map(\.id)
        return (soon, planned)
    }

    @Test func noPageShowsBientotUnlessItIsNamed() {
        defer { SettingsPageBodies.removeAll() }
        let (soon, planned) = wireEveryLane()
        print("SWEEP coming soon: \(soon)")
        print("SWEEP planned rows: \(planned)")
        for id in soon + planned {
            #expect(Self.stillPending[id] != nil, "\(id) still shows Bientôt and nobody owns it")
        }
    }

    @Test func theTwoToolsThisLaneWiredAreGone() {
        defer { SettingsPageBodies.removeAll() }
        let (soon, planned) = wireEveryLane()
        for id in ["forcequit", "ports", "menubar", "island", "quickpanel", "quickactions"] {
            #expect(!soon.contains(id) && !planned.contains(id), "\(id)")
        }
    }

    @Test func theAppDelegateRegistersTheIslandEditorsAndTheQuickPanel() throws {
        let text = try String(contentsOf: PortSourceScrubTests.repoRoot.appendingPathComponent("Sources/MacIsland/AppDelegate.swift"), encoding: .utf8)
        #expect(text.contains("SettingsPageBodies.register(pageID: \"island\")"))
        #expect(text.contains("onTogglePanel"), "the status item opens the quick panel")
    }

    @Test func everyNamedPageExists() {
        for id in Self.stillPending.keys { #expect(SettingsPageCatalog.page(id) != nil, "\(id)") }
    }
}
