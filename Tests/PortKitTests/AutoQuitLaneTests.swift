import AppKit
import Foundation
import IslandKit
import IslandTestSupport
import SwiftUI
import Testing
@testable import PortKit
@testable import ShellKit

/// Lane W3D (auto-quit and Spaces order): the two features bound through `PortFeatureBinding` with a FAKE runtime,
/// so no Accessibility observer, event tap, preference write or Dock restart happens here. Covers the descriptors
/// and permission tables, off by default, the permission gate, start/stop through the registry, the kill switch,
/// safe mode, the quit hook, the retired Display module and the two Settings pages.
@MainActor
@Suite(.serialized) struct AutoQuitLaneTests {
    static let ids = ["autoQuit", "spacesOrder"]

    final class FakeRuntime {
        var events: [String] = []
        func count(_ event: String) -> Int { events.filter { $0 == event }.count }
        var runtime: AutoQuitSpacesLane.Runtime {
            AutoQuitSpacesLane.Runtime(
                syncAutoQuit: { [self] in events.append("syncAutoQuit") },
                stopAutoQuit: { [self] in events.append("stopAutoQuit") },
                syncSpaces: { [self] in events.append("syncSpaces") },
                stopSpaces: { [self] in events.append("stopSpaces") },
                restoreBeforeTermination: { [self] in events.append("restoreBeforeTermination") })
        }
    }

    struct Rig {
        let binding: PortFeatureBinding
        let registry: FeatureRegistry
        let fake: FakeRuntime
        let permissions: Box<PortPermissionState>
        let cleanup: () -> Void
    }

    func rig(granted: PortPermissionState = PortPermissionState(accessibility: true), switchedOn: Bool = true) -> Rig {
        let permissions = Box(granted)
        let binding = PortFeatureBinding(permissions: { permissions.value })
        let fake = FakeRuntime()
        AutoQuitSpacesLane.bind(into: binding, runtime: fake.runtime)
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let probe = PermissionProbe(accessibility: { permissions.value.accessibility },
                                    screenRecording: { permissions.value.screenRecording },
                                    inputMonitoring: { permissions.value.inputMonitoring }, automation: { _ in nil })
        let registry = FeatureRegistry(descriptors: binding.descriptors, defaults: bench.defaults, crashMarker: marker,
                                       capabilityProvider: SystemCapabilities.provider(probe), withdraw: { _ in })
        binding.connectAvailability()
        if switchedOn { for d in binding.descriptors { registry.switches[d.id] = true } }
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        return Rig(binding: binding, registry: registry, fake: fake, permissions: permissions,
                   cleanup: { bench.cleanup(); marker.clear() })
    }

    func change(_ rig: Rig, to new: PortPermissionState) {
        let old = rig.permissions.value
        rig.permissions.value = new
        rig.registry.permissionsChanged(PermissionChange(
            old: PermissionSnapshot(accessibility: old.accessibility, inputMonitoring: old.inputMonitoring,
                                    screenRecording: old.screenRecording),
            new: PermissionSnapshot(accessibility: new.accessibility, inputMonitoring: new.inputMonitoring,
                                    screenRecording: new.screenRecording)))
    }

    // MARK: Descriptors and permission tables

    @Test func theLaneBindsAutoQuitAndSpacesOrderWithFrenchTextAndTheCatalogsPermissions() {
        PortHostFixture.isolated { _ in
            let binding = PortFeatureBinding(permissions: { PortPermissionState() })
            AutoQuitSpacesLane.bind(into: binding, runtime: FakeRuntime().runtime)
            #expect(binding.descriptors.map(\.id) == Self.ids)
            let byID = Dictionary(uniqueKeysWithValues: binding.descriptors.map { ($0.id, $0) })
            for d in binding.descriptors {
                #expect(d.category == .windows, "\(d.id)")
                #expect(!d.enabledByDefault, "\(d.id): off until the person turns it on")
                #expect(!d.title.isEmpty && !d.summary.isEmpty, "\(d.id)")
                #expect(!d.title.contains("Keep Spaces") && !d.title.contains("Quit on"), "French, not English: \(d.title)")
            }
            // Upstream's table: auto-quit needs Accessibility (window observers), the Spaces order needs nothing.
            #expect(byID["autoQuit"]?.permissions == [.accessibility] && byID["autoQuit"]?.risk == .touchesInput)
            #expect(byID["spacesOrder"]?.permissions == [] && byID["spacesOrder"]?.risk == .touchesSystem,
                    "it changes a system setting and restarts the Dock")
            #expect(byID["autoQuit"]?.title.contains("fermeture") == true && byID["spacesOrder"]?.title.contains("Espaces") == true)
            #expect(AppFeature.autoQuit.permissions == [.accessibility] && AppFeature.spacesOrder.permissions.isEmpty)
        }
    }

    @Test func theLiveLaneBindsTheSameTwoAndPortLanesListsIt() {
        PortHostFixture.isolated { _ in
            defer { AutoQuitSpacesLane.removeTerminationHook() }
            let binding = PortFeatureBinding(permissions: { PortPermissionState() })
            AutoQuitSpacesLane.bind(into: binding, runtime: .live)
            #expect(binding.descriptors.map(\.id) == Self.ids)
            let scratch = PortFeatureBinding(permissions: { PortPermissionState() })
            PortLanes.bindAll(into: scratch)
            defer { DisplayBrightnessLane.removeTerminationHook() }
            #expect(Self.ids.allSatisfy { id in scratch.descriptors.contains { $0.id == id } }, "PortLanes runs the lane")
        }
    }

    @Test func neitherFeatureCollidesWithOneOfOurOwnModules() {
        #expect(!PortFeatureIDs.isOwnedByExistingModule("autoQuit"))
        #expect(!PortFeatureIDs.isOwnedByExistingModule("spacesOrder"))
        #expect(AppFeature.autoQuit.registryID == "autoQuit" && AppFeature.spacesOrder.registryID == "spacesOrder")
        #expect(!ShellDescriptors.all.contains { $0.id == "autoQuit" || $0.id == "spacesOrder" })
    }

    @Test func theDisplayModuleIsRetiredAndNothingKeepsItsPages() {
        #expect(!ShellDescriptors.all.contains { $0.id == "display" }, "no registry feature, switch or tab 'display'")
        #expect(!ShellDescriptors.all.contains { $0.tabID == "display" })
        let page = SettingsPageCatalog.page("quitonclose")!
        #expect(page.featureID == nil, "the binding adds the feature card, the catalog must not point at 'display'")
        #expect(SettingsLive.controls(for: "quitonclose") == nil, "the greyed live rows were replaced by the ported page")
        #expect(SettingsPageCatalog.page("spaces")!.featureID == nil)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources/Features/Display").path))
    }

    // MARK: Off by default, permission gate, idempotence

    @Test func everythingIsOffAndNothingRunsUntilTheSwitchesAreOn() {
        PortHostFixture.isolated { _ in
            let r = rig(switchedOn: false)
            defer { r.cleanup() }
            #expect(r.fake.events.isEmpty, "a launch with the switches off starts nothing, restarts no Dock")
            for id in Self.ids { #expect(r.registry.state(for: id) == .off, "\(id)") }
        }
    }

    @Test func autoQuitWaitsForAccessibilityButTheSpacesOrderDoesNot() {
        PortHostFixture.isolated { _ in
            let r = rig(granted: PortPermissionState())
            defer { r.cleanup() }
            #expect(r.fake.count("syncAutoQuit") == 0, "Accessibility missing: the service was never touched")
            #expect(r.registry.state(for: "autoQuit") == .needsPermission(.accessibility))
            #expect(r.fake.count("syncSpaces") == 1 && r.registry.state(for: "spacesOrder") == .active)
            change(r, to: PortPermissionState(accessibility: true))
            #expect(r.binding.isStarted("autoQuit"))
            #expect(r.fake.events.filter { $0 == "syncAutoQuit" || $0 == "stopAutoQuit" }.last == "syncAutoQuit")
        }
    }

    @Test func startIsIdempotent() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            let before = r.fake.events
            for id in Self.ids { r.binding.starters[id]!() }
            #expect(r.fake.events == before, "a second start of a running feature reaches nothing")
        }
    }

    @Test func neverARegistryStartWithoutTheSwitch() {
        PortHostFixture.isolated { _ in
            let r = rig(switchedOn: false)
            defer { r.cleanup() }
            // The page toggle alone changes nothing the registry did not allow: turning it on reaches no service
            // (the services read `isAvailable`, which is the registry's verdict).
            #expect(r.binding.availability("spacesOrder") == false && r.binding.availability("autoQuit") == false)
            PortHost.defaults.set(true, forKey: DefaultsKey.spacesOrderEnabled)
            #expect(!AppFeature.spacesOrder.isAvailable)
            #expect(!AppFeature.autoQuit.isAvailable)
        }
    }

    // MARK: Stops: the escape hatch

    @Test func theKillSwitchStopsBothAndLiftingItStartsThemAgain() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            r.fake.events.removeAll()
            r.registry.killSwitch = true
            #expect(r.fake.count("stopAutoQuit") == 1, "observers and the click monitor go away")
            #expect(r.fake.count("stopSpaces") == 1, "the Dock setting is given back")
            for id in Self.ids { #expect(r.registry.state(for: id) == .killed, "\(id)") }
            r.fake.events.removeAll()
            r.registry.killSwitch = false
            #expect(r.fake.count("syncAutoQuit") == 1 && r.fake.count("syncSpaces") == 1)
        }
    }

    @Test func safeModeAndARevokedGrantStopTheServices() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            r.fake.events.removeAll()
            r.registry.safeMode = true
            #expect(r.fake.count("stopAutoQuit") == 1 && r.fake.count("stopSpaces") == 1)
            r.registry.safeMode = false
            r.fake.events.removeAll()
            change(r, to: PortPermissionState())
            #expect(r.fake.count("stopAutoQuit") == 1, "auto-quit uses Accessibility: a revoke stops it")
            #expect(r.fake.count("stopSpaces") == 0, "the Spaces order uses no permission and keeps running")
        }
    }

    @Test func turningASwitchOffStopsThatFeatureOnly() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            r.fake.events.removeAll()
            r.registry.switches["spacesOrder"] = false
            #expect(r.fake.events == ["stopSpaces"], "\(r.fake.events)")
            #expect(r.binding.availability("spacesOrder") == false && r.binding.availability("autoQuit") == true)
        }
    }

    @Test func theRegistryMakesTheAvailabilityTheUpstreamServicesRead() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            #expect(r.binding.availability("autoQuit") == true && r.binding.availability("spacesOrder") == true)
            r.registry.killSwitch = true
            #expect(r.binding.availability("autoQuit") == false && r.binding.availability("spacesOrder") == false,
                    "AppFeature.isAvailable is false the moment the kill switch is on: syncWithPreferences stops too")
        }
    }

    // MARK: Quit

    @Test func theQuitHookRestoresThroughTheRuntimeAndIsInstalledOnce() {
        PortHostFixture.isolated { _ in
            AutoQuitSpacesLane.removeTerminationHook()
            defer { AutoQuitSpacesLane.removeTerminationHook() }
            let fake = FakeRuntime()
            AutoQuitSpacesLane.installTerminationHook(runtime: fake.runtime)
            AutoQuitSpacesLane.installTerminationHook(runtime: FakeRuntime().runtime)
            NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
            #expect(fake.count("restoreBeforeTermination") == 1, "the first hook only; the second install was refused")
        }
    }

    @Test func theLiveStopsAndTheQuitRestoreTouchNothingWhenNothingIsOwed() {
        PortHostFixture.isolated { defaults in
            #expect(!SpacesOrderHold.hasPendingRestore)
            // No marker, no owed restart: these must not build the hold or reach the Dock (the live system would).
            AutoQuitSpacesLane.Runtime.live.stopSpaces()
            AutoQuitSpacesLane.Runtime.live.restoreBeforeTermination()
            AutoQuitSpacesLane.Runtime.live.stopAutoQuit()
            #expect(defaults.string(forKey: DefaultsKey.spacesOrderRestore) == nil)
        }
    }

    // MARK: Settings pages

    @Test func thePagesReplaceTheComingSoonRows() {
        PortHostFixture.isolated { _ in
            SettingsPageBodies.removeAll()
            defer { SettingsPageBodies.removeAll() }
            let r = rig(switchedOn: false)
            defer { r.cleanup() }
            let pages = r.binding.pages
            #expect(pages.map(\.pageID) == ["quitonclose", "spaces"])
            #expect(pages.map(\.featureID) == Self.ids)
            for ported in pages {
                let page = SettingsPageCatalog.page(ported.pageID)!
                #expect(page.featureID == nil, "\(ported.pageID): the binding adds the feature card, the catalog must not")
                #expect(page.isComingSoon, "\(ported.pageID): a stub until the body is registered")
                SettingsPageBodies.register(pageID: ported.pageID, featureID: ported.featureID, registry: r.registry,
                                            openPermission: { _ in }, ported.body)
                #expect(!page.isComingSoon, "\(ported.pageID)")
                #expect(SettingsPageModel.blocks(for: page).isEmpty, "\(ported.pageID): no greyed 'Bientôt' row stays")
            }
        }
    }

    @Test func theTwoPagesRenderWhileTheFeaturesAreOff() {
        PortHostFixture.isolated { _ in
            let r = rig(switchedOn: false)
            defer { r.cleanup() }
            for ported in r.binding.pages {
                let host = NSHostingView(rootView: ported.body())
                host.frame = NSRect(x: 0, y: 0, width: 720, height: 900)
                host.layoutSubtreeIfNeeded()
                #expect(host.fittingSize.height > 80, "\(ported.pageID) rendered \(host.fittingSize): empty while the feature is off")
            }
        }
    }

    @Test func thePagesCarryTheStatesAPersonNeedsToTrustThem() throws {
        let text = try String(contentsOf: Self.sources.appendingPathComponent("Bridge/AutoQuitPages.swift"), encoding: .utf8)
        for needed in ["Simulation seulement", "Jamais quittées", "Le Dock redémarre une fois", "rétabli quand la fonction s’arrête"] {
            #expect(text.contains(needed), "\(needed)")
        }
    }

    // MARK: Source contract (read from the files, nothing runs)

    private static let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/PortKit")

    @Test func theOnlyDockRestartOfThePortIsTheGuardedOne() throws {
        var offenders: [String] = []
        for root in ["Services", "Bridge", "UI", "Core", "App"] {
            let dir = Self.sources.appendingPathComponent(root)
            guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                let text = try String(contentsOf: url, encoding: .utf8)
                for line in text.split(separator: "\n") where !line.drop(while: { $0 == " " }).hasPrefix("//") {
                    if line.contains("killall"), line.contains("Dock") { offenders.append(url.lastPathComponent) }
                }
            }
        }
        #expect(offenders == ["AutoQuitSpacesGuard.swift"], "\(offenders)")
        let hold = try String(contentsOf: Self.sources.appendingPathComponent("Services/SpacesOrder/SpacesOrderHold.swift"),
                              encoding: .utf8)
        #expect(hold.contains("restartDock: { SpacesDockRestartGuard.shared.restart() }"), "patch 0851 is applied")
    }
}
