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
    /// Page id -> why it is not wired yet. One owner each. Lanes A to D wired monitor, fans, cutpaste, renameshortcut,
    /// cleaner, appupdates, homebrew, uninstaller and the rest: only the two pages below still carry greyed rows, and
    /// `everyPinnedPageStillShowsSomething` fails when an entry here goes stale.
    static let stillPending: [String: String] = [
        "clipboard": "decision of W5A: our Clipboard module keeps the history. Live: history, limit, auto clear, images and "
            + "files, paste as files. Greyed, no module behind them: sensitive filter, retention, layout, menu bar preview, "
            + "popover shortcut",
        "pasteplain": "decision of W5A: our Clipboard module owns the plain-paste shortcut (live); the pinned and recent lists "
            + "of the reference page are the history pane's job (greyed)",
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
        #expect(text.contains("SettingsPageBodies.registerComposed(pageID: \"island\")"))
        #expect(text.contains("onTogglePanel"), "the status item opens the quick panel")
    }

    @Test func everyNamedPageExists() {
        for id in Self.stillPending.keys { #expect(SettingsPageCatalog.page(id) != nil, "\(id)") }
    }

    @Test func everyPinnedPageStillShowsSomething() {
        defer { SettingsPageBodies.removeAll() }
        let (soon, planned) = wireEveryLane()
        for id in Self.stillPending.keys {
            #expect(soon.contains(id) || planned.contains(id), "\(id) is pinned as pending but shows no Bientôt row any more")
        }
    }

    @Test func theMenuBarPageAndTheOtherPagesAreDrawnByOneRouteEach() {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        PortLanes.bindAll(into: binding)
        let bound = binding.pages.map(\.pageID)
        #expect(Set(bound).count == bound.count, "two bound features draw the same page")
        let overlap = Set(bound).intersection(PortBridge.registeredPageIDs)
        #expect(overlap.isEmpty, "\(overlap.sorted()) is drawn by both PortBridge and a bound feature")
        #expect(!Set(bound + PortBridge.registeredPageIDs).contains("island"), "the island page is the app delegate's")
        #expect(PortBridge.registeredPageIDs.contains("menubar"))
    }

    @Test func aPageTwoLanesDrawKeepsBothBodies() {
        SettingsPageBodies.removeAll()
        defer { SettingsPageBodies.removeAll() }
        var built: [String] = []
        SettingsPageBodies.register(pageID: "menubar") { built.append("quickpanel"); return AnyView(EmptyView()) }
        SettingsPageBodies.registerComposed(pageID: "menubar") { built.append("monitor"); return AnyView(EmptyView()) }
        #expect(SettingsPageBodies.hasBody(for: "menubar"))
        _ = SettingsPageBodies.body(for: "menubar")
        #expect(built == ["quickpanel", "monitor"], "the last registration does not erase the first")
        // A plain register still replaces (the documented behaviour tests rely on).
        built = []
        SettingsPageBodies.register(pageID: "menubar") { built.append("only"); return AnyView(EmptyView()) }
        _ = SettingsPageBodies.body(for: "menubar")
        #expect(built == ["only"])
    }

    @Test func theClipboardPageGotItsImagesAndFilesRowLive() throws {
        let page = try #require(SettingsLive.controls(for: "clipboard"))
        #expect(page.bound["Enregistrer aussi les images et fichiers copiés"]?.key == "clipboardHistoryIncludeImagesFiles")
    }
}
