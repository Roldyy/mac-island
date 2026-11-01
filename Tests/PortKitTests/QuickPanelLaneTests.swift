import AppKit
import Foundation
import IslandTestSupport
import SwiftUI
import Testing
@testable import PortKit
@testable import ShellKit

/// Lane G, quick panel and menu bar page. No popover is shown here: the panel needs a status item and a window server
/// click, so what is pinned is the policy (pure), the nothing-at-launch rule and the page registration.
@MainActor
@Suite(.serialized) struct QuickPanelLaneTests {
    @Test func nothingIsBuiltBeforeTheFirstClick() {
        #expect(!PortQuickPanel.shared.isShown)
        // Closing a panel that never opened is a no-op, not a crash.
        PortQuickPanel.shared.close()
        PortQuickPanel.shared.close(force: true)
        #expect(!PortQuickPanel.shared.isShown)
    }

    @Test func aClickOutsideClosesAndAClickOnThePanelOrTheIconDoesNot() {
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        let icon = NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        let other = NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        #expect(PortQuickPanel.dismisses(clickIn: nil, panelWindow: panel, anchorWindow: icon), "another app")
        #expect(PortQuickPanel.dismisses(clickIn: other, panelWindow: panel, anchorWindow: icon), "Settings or the island")
        #expect(!PortQuickPanel.dismisses(clickIn: panel, panelWindow: panel, anchorWindow: icon))
        #expect(!PortQuickPanel.dismisses(clickIn: icon, panelWindow: panel, anchorWindow: icon), "the icon's own action toggles")
    }

    @Test func aRunningWorkflowKeepsThePanelOpen() {
        // The one answer every dismissal path asks: fresh state keeps nothing open.
        let state = PanelInteractionState.shared
        let saved = (state.viewKeepsPopoverOpen, state.isPresentingPopoverModal)
        defer { (state.viewKeepsPopoverOpen, state.isPresentingPopoverModal) = saved }
        state.viewKeepsPopoverOpen = false
        state.isPresentingPopoverModal = false
        #expect(!state.preventsPopoverDismissal)
        state.isPresentingPopoverModal = true
        #expect(state.preventsPopoverDismissal)
        state.isPresentingPopoverModal = false
        state.viewKeepsPopoverOpen = true
        #expect(state.preventsPopoverDismissal)
    }

    @Test func theMenuBarPageHasAPortedBodyAndNoLeftoverRows() throws {
        let page = try #require(SettingsPageCatalog.page(QuickPanelLane.pageID))
        QuickPanelLane.bind(into: PortFeatureBinding(permissions: { PortPermissionState() }))
        #expect(PortBridge.registeredPageIDs.contains("menubar"))
        #expect(PortBridge.settingsBody(pageID: "menubar") != nil)
        SettingsPageBodies.removeAll()
        defer { SettingsPageBodies.removeAll() }
        SettingsPageBodies.register(pageID: "menubar") { PortBridge.settingsBody(pageID: "menubar") ?? AnyView(EmptyView()) }
        #expect(SettingsPageModel.blocks(for: page).flatMap(\.rows).allSatisfy { $0.isLive }, "no greyed Bientôt row stays")
        #expect(!page.isComingSoon)
    }

    @Test func theLaneIsListedInPortLanes() throws {
        let text = try String(contentsOf: PortSourceScrubTests.portKit.appendingPathComponent("Bridge/PortLanes.swift"), encoding: .utf8)
        #expect(text.contains("QuickPanelLane.bind(into:)"))
        #expect(text.contains("KillPortsLane.bind(into:)"))
    }

    /// The popover is the app's, not upstream's: no second status item, no event tap, no private symbol in the lane file.
    @Test func theLaneFileCreatesNoStatusItemAndUsesNoPrivateApi() throws {
        let text = try String(contentsOf: PortSourceScrubTests.portKit.appendingPathComponent("Bridge/QuickPanel.swift"), encoding: .utf8)
        for forbidden in ["NSStatusBar", "CGEvent.tapCreate", "dlsym", "@_silgen_name", "NSAppleScript"] {
            #expect(!text.contains(forbidden), "\(forbidden)")
        }
    }

    @Test func rendersTheMenuBarPage() throws {
        let bench = TestDefaults.make(); defer { bench.cleanup() }
        let dir = ProcessInfo.processInfo.environment["MIS_RENDER_DIR"] ?? NSTemporaryDirectory()
        let host = NSHostingView(rootView: MenuBarPanelPage().defaultAppStorage(bench.defaults).frame(width: 700, height: 1000)
            .background(Color(nsColor: .windowBackgroundColor)))
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 1000)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("settings-menubar-panel.png"))
        #expect(png.count > 5_000)
    }
}
