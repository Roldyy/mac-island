import AppKit
import Foundation
import SwiftUI
import Testing
@testable import PortKit
@testable import ShellKit

@MainActor
@Suite(.serialized) struct InputShortcutsOwnershipTests {
    @Test func keepAwakeHasOneOwnerAndTheKeepsTheKeysHaroldHas() {
        #expect(!PortShortcutOwnership.upstreamKeepAwakeHotkeyAllowed, "only KeepAwakeShortcutService registers it")
        PortHostFixture.isolated { defaults in
            #expect(PortShortcutOwnership.keepAwakeDisplay(in: defaults) == "⌃⌥⌘K", "the default is kept")
            defaults.set("control+option+command:j", forKey: DefaultsKey.keepAwakeShortcut)  // our own format
            #expect(PortShortcutOwnership.keepAwakeDisplay(in: defaults) == "⌃⌥⌘J")
            defaults.set(false, forKey: "keepAwakeShortcutEnabled")
            #expect(PortShortcutOwnership.keepAwakeDisplay(in: defaults) == nil)
        }
    }

    @Test func theUpstreamKeepAwakeRegistrarIsGuardedInTheSource() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/PortKit/Services/HotkeyManager.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("guard PortShortcutOwnership.upstreamKeepAwakeHotkeyAllowed"))
    }

    @Test func bothSpellingsOfAStoredShortcutAreRead() {
        let named = GlobalShortcut(storageValue: "control+option+command:k")
        #expect(named == .keepAwakeDefault)
        #expect(GlobalShortcut(storageValue: "control+option+command:40") == .keepAwakeDefault)
        #expect(GlobalShortcut(storageValue: "option:space") == GlobalShortcut(keyCode: 49, modifiers: [.option]))
        #expect(GlobalShortcut(storageValue: "control:nonsense") == nil)
        #expect(GlobalShortcut(storageValue: "k") == nil)
    }

    @Test func boundAndRunningFollowTheRegistry() {
        PortHostFixture.isolated { _ in
            #expect(!PortShortcutOwnership.isBound(.cleaningMode))
            PortHost.availability = { $0 == "cleaningMode" ? false : nil }
            #expect(PortShortcutOwnership.isBound(.cleaningMode) && !PortShortcutOwnership.isRunning(.cleaningMode))
            #expect(!PortShortcutOwnership.isBound(.keepAwake), "our own module's feature is never bound")
            PortHost.availability = { $0 == "cleaningMode" ? true : nil }
            #expect(PortShortcutOwnership.isRunning(.cleaningMode))
        }
    }

    @Test func theLaneBindsCleaningModeOffByDefaultWithItsPageAndTheShortcutsPage() {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        InputShortcutsLane.bind(into: binding)
        #expect(binding.descriptors.map(\.id) == ["cleaningMode"])
        let d = binding.descriptors[0]
        #expect(!d.enabledByDefault && d.permissions == [.accessibility] && d.risk == .touchesInput)
        #expect(binding.pages.map(\.pageID) == ["cleaning"])
        #expect(PortBridge.registeredPageIDs.contains("shortcuts"))
        #expect(SettingsPageCatalog.page("cleaning") != nil && SettingsPageCatalog.page("shortcuts") != nil)
        #expect(SettingsPageCatalog.page("cleaning")?.featureID == nil, "the page opens with the bound feature's card")
        #expect(MonitoredPermission.used(by: d) == [.accessibility])
    }

    @Test func bothPagesHaveABodyAndStopReadingComingSoon() {
        SettingsPageBodies.removeAll()
        defer { SettingsPageBodies.removeAll() }
        let cleaning = SettingsPageCatalog.page("cleaning")!, shortcuts = SettingsPageCatalog.page("shortcuts")!
        #expect(cleaning.isComingSoon && shortcuts.isComingSoon)
        SettingsPageBodies.register(pageID: "cleaning") { AnyView(CleaningModePage()) }
        SettingsPageBodies.register(pageID: "shortcuts") { AnyView(ShortcutsPage()) }
        #expect(!cleaning.isComingSoon && !shortcuts.isComingSoon)
    }

    @Test func thePageBodiesRender() {
        PortHostFixture.isolated { _ in
            for view in [AnyView(CleaningModePage()), AnyView(ShortcutsPage().defaultAppStorage(PortHost.defaults))] {
                let host = NSHostingView(rootView: view)
                host.frame = NSRect(x: 0, y: 0, width: 640, height: 600)
                host.layoutSubtreeIfNeeded()
                #expect(host.fittingSize.height > 60, "rendered: \(host.fittingSize)")
            }
        }
    }

    @Test func recordingAShortcutStartsNothingForAnUnboundFeature() {
        PortHostFixture.isolated { _ in
            PortHost.availability = { $0 == "scrollInverter" ? true : nil }
            let silenced = GlobalShortcutRole.featuresToSilenceWhileRecording.filter(PortShortcutOwnership.isBound)
            #expect(!silenced.contains(.keepAwake) && !silenced.contains(.clipboardHistory))
            #expect(!silenced.contains(.shelf) && !silenced.contains(.commandBar))
        }
    }
}
