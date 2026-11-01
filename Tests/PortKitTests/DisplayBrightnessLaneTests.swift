import AppKit
import Foundation
import IslandKit
import IslandTestSupport
import SwiftUI
import Testing
@testable import PortKit
@testable import ShellKit

/// Lane W2A (display, brightness, keyboard light): the two features bound through `PortFeatureBinding` with a FAKE
/// runtime, so no display, IOKit service or CoreBrightness client is ever touched here. Covers the descriptors, off
/// by default, the permission gate, start/stop through the registry, the kill switch, safe mode, the switch
/// adoption from our old Display module, the Settings pages and the source contract (no prompt, no new private
/// symbol site).
@MainActor
@Suite(.serialized) struct DisplayBrightnessLaneTests {
    static let ids = ["brightness", "extraBrightness"]

    final class FakeRuntime {
        var events: [String] = []
        func count(_ event: String) -> Int { events.filter { $0 == event }.count }
        var runtime: DisplayBrightnessLane.Runtime {
            DisplayBrightnessLane.Runtime(
                syncBrightness: { [self] in events.append("syncBrightness") },
                stopBrightness: { [self] in events.append("stopBrightness") },
                syncExtraBrightness: { [self] in events.append("syncExtra") },
                stopExtraBrightness: { [self] in events.append("stopExtra") },
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
        DisplayBrightnessLane.bind(into: binding, runtime: fake.runtime)
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

    // MARK: Descriptors and permission table

    @Test func theLaneBindsBrightnessAndExtraBrightnessWithFrenchTextAndTheCatalogsPermissions() {
        PortHostFixture.isolated { _ in
            let binding = PortFeatureBinding(permissions: { PortPermissionState() })
            DisplayBrightnessLane.bind(into: binding, runtime: FakeRuntime().runtime)
            #expect(binding.descriptors.map(\.id) == Self.ids)
            let byID = Dictionary(uniqueKeysWithValues: binding.descriptors.map { ($0.id, $0) })
            for d in binding.descriptors {
                #expect(d.category == .display, "\(d.id)")
                #expect(d.risk == .touchesSystem, "\(d.id): changes a system setting")
                #expect(!d.enabledByDefault, "\(d.id)")
                #expect(!d.title.isEmpty && !d.summary.isEmpty, "\(d.id)")
                #expect(!d.title.contains("rightness"), "French, not English: \(d.title)")
            }
            // Upstream's table: the brightness keys need Accessibility, the XDR overlay needs nothing.
            #expect(byID["brightness"]?.permissions == [.accessibility])
            #expect(byID["extraBrightness"]?.permissions == [])
            #expect(AppFeature.brightness.permissions == [.accessibility] && AppFeature.extraBrightness.permissions.isEmpty)
        }
    }

    @Test func theLiveLaneBindsTheSameTwoAndPortLanesListsIt() {
        PortHostFixture.isolated { _ in
            let binding = PortFeatureBinding(permissions: { PortPermissionState() })
            DisplayBrightnessLane.bind(into: binding, runtime: .live)
            #expect(binding.descriptors.map(\.id) == Self.ids)
            defer { DisplayBrightnessLane.removeTerminationHook() }
            let scratch = PortFeatureBinding(permissions: { PortPermissionState() })
            PortLanes.bindAll(into: scratch)
            #expect(Self.ids.allSatisfy { id in scratch.descriptors.contains { $0.id == id } },
                    "PortLanes runs the display lane")
        }
    }

    @Test func neitherFeatureCollidesWithOneOfOurOwnModules() {
        #expect(!PortFeatureIDs.isOwnedByExistingModule("brightness"))
        #expect(!PortFeatureIDs.isOwnedByExistingModule("extraBrightness"))
        #expect(AppFeature.brightness.registryID == "brightness")
        #expect(ShellDescriptors.all.contains { $0.id == "display" }, "the Display tab stays: it hosts auto-quit")
        #expect(!ShellDescriptors.all.contains { $0.id == "brightness" || $0.id == "extraBrightness" })
    }

    // MARK: Off by default, permission gate, idempotence

    @Test func everythingIsOffAndNothingRunsUntilTheSwitchesAreOn() {
        PortHostFixture.isolated { _ in
            let r = rig(switchedOn: false)
            defer { r.cleanup() }
            #expect(r.fake.events.isEmpty)
            for id in Self.ids { #expect(r.registry.state(for: id) == .off, "\(id)") }
        }
    }

    @Test func brightnessWaitsForAccessibilityButExtraBrightnessDoesNot() {
        PortHostFixture.isolated { _ in
            let r = rig(granted: PortPermissionState())
            defer { r.cleanup() }
            #expect(r.fake.count("syncBrightness") == 0, "Accessibility missing: the display service was never touched")
            #expect(r.registry.state(for: "brightness") == .needsPermission(.accessibility))
            #expect(r.fake.count("syncExtra") == 1 && r.registry.state(for: "extraBrightness") == .active)
            change(r, to: PortPermissionState(accessibility: true))
            #expect(r.binding.isStarted("brightness"))
            #expect(r.fake.events.filter { $0 == "syncBrightness" || $0 == "stopBrightness" }.last == "syncBrightness")
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

    // MARK: Stops: the escape hatch

    @Test func theKillSwitchStopsBothAndLiftingItStartsThemAgain() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            r.fake.events.removeAll()
            r.registry.killSwitch = true
            #expect(r.fake.count("stopBrightness") == 1 && r.fake.count("stopExtra") == 1,
                    "one stop each: gamma and switched-off displays go back, the XDR overlay goes away")
            for id in Self.ids { #expect(r.registry.state(for: id) == .killed, "\(id)") }
            r.fake.events.removeAll()
            r.registry.killSwitch = false
            #expect(r.fake.count("syncBrightness") == 1 && r.fake.count("syncExtra") == 1)
        }
    }

    @Test func safeModeAndARevokedGrantStopTheServices() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            r.fake.events.removeAll()
            r.registry.safeMode = true
            #expect(r.fake.count("stopBrightness") == 1 && r.fake.count("stopExtra") == 1)
            r.registry.safeMode = false
            r.fake.events.removeAll()
            change(r, to: PortPermissionState())
            #expect(r.fake.count("stopBrightness") == 1, "brightness uses Accessibility: a revoke stops it")
            #expect(r.fake.count("stopExtra") == 0, "the XDR overlay uses no permission and keeps running")
        }
    }

    @Test func theRegistryMakesTheAvailabilityTheUpstreamServicesRead() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            #expect(r.binding.availability("brightness") == true)
            r.registry.killSwitch = true
            #expect(r.binding.availability("brightness") == false && r.binding.availability("extraBrightness") == false,
                    "AppFeature.isAvailable is false the moment the kill switch is on: syncWithPreferences stops too")
        }
    }

    // MARK: Switch adoption from our old Display module

    @Test func anOldDisplaySwitchThatWasOnKeepsBrightnessOnWithItsToggle() {
        PortHostFixture.isolated { defaults in
            defaults.set(true, forKey: "shell.enabled.display")
            DisplayBrightnessLane.adoptOldDisplaySwitch(in: defaults, brightnessControlStored: { _ in false })
            #expect(defaults.object(forKey: "shell.enabled.brightness") as? Bool == true)
            #expect(defaults.bool(forKey: DefaultsKey.brightnessControlEnabled),
                    "the old module read an absent key as ON")
            #expect(defaults.bool(forKey: DisplayBrightnessLane.adoptionDoneKey))
        }
    }

    @Test func adoptionNeverOverridesAChoiceAndRunsOnce() {
        PortHostFixture.isolated { defaults in
            defaults.set(true, forKey: "shell.enabled.display")
            defaults.set(false, forKey: "shell.enabled.brightness")  // migrated from the Vorssaint switch: off
            defaults.set(false, forKey: DefaultsKey.brightnessControlEnabled)
            DisplayBrightnessLane.adoptOldDisplaySwitch(in: defaults, brightnessControlStored: { _ in true })
            #expect(defaults.object(forKey: "shell.enabled.brightness") as? Bool == false)
            #expect(!defaults.bool(forKey: DefaultsKey.brightnessControlEnabled))
            // Done: a later removal of the choice is not adopted again.
            defaults.removeObject(forKey: "shell.enabled.brightness")
            DisplayBrightnessLane.adoptOldDisplaySwitch(in: defaults, brightnessControlStored: { _ in false })
            #expect(defaults.object(forKey: "shell.enabled.brightness") == nil)

            // A stored toggle is kept even when the old switch was on and the new one never chosen.
            defaults.removeObject(forKey: DisplayBrightnessLane.adoptionDoneKey)
            DisplayBrightnessLane.adoptOldDisplaySwitch(in: defaults, brightnessControlStored: { _ in true })
            #expect(defaults.object(forKey: "shell.enabled.brightness") as? Bool == true)
            #expect(!defaults.bool(forKey: DefaultsKey.brightnessControlEnabled), "the person's own off stays off")
        }
    }

    @Test func aDisplaySwitchThatWasOffAdoptsNothing() {
        PortHostFixture.isolated { defaults in
            defaults.set(false, forKey: "shell.enabled.display")
            DisplayBrightnessLane.adoptOldDisplaySwitch(in: defaults, brightnessControlStored: { _ in false })
            #expect(defaults.object(forKey: "shell.enabled.brightness") == nil)
            #expect(!defaults.bool(forKey: DefaultsKey.brightnessControlEnabled), "no toggle was turned on for it")
        }
    }

    // MARK: Quit and launch

    @Test func theQuitHookRestoresThroughTheRuntimeAndIsInstalledOnce() {
        PortHostFixture.isolated { _ in
            // The live lane installs the same hook when PortLanes binds it: start from none.
            DisplayBrightnessLane.removeTerminationHook()
            defer { DisplayBrightnessLane.removeTerminationHook() }
            let fake = FakeRuntime()
            DisplayBrightnessLane.installTerminationHook(runtime: fake.runtime)
            DisplayBrightnessLane.installTerminationHook(runtime: FakeRuntime().runtime)
            NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
            #expect(fake.count("restoreBeforeTermination") == 1, "the first hook only; the second install was refused")
        }
    }

    // MARK: Settings pages

    @Test func displaysAndExtraBrightnessPagesReplaceTheComingSoonRows() {
        PortHostFixture.isolated { _ in
            SettingsPageBodies.removeAll()
            defer { SettingsPageBodies.removeAll() }
            let r = rig(switchedOn: false)
            defer { r.cleanup() }
            let pages = r.binding.pages
            #expect(pages.map(\.pageID) == ["displays", "extrabrightness"])
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

    @Test func theKeyboardLightPageIsRegisteredAndBelongsToBrightness() {
        PortHostFixture.isolated { _ in
            let binding = PortFeatureBinding(permissions: { PortPermissionState() })
            DisplayBrightnessLane.bind(into: binding, runtime: FakeRuntime().runtime)
            #expect(PortBridge.registeredPageIDs.contains("kbdlight"))
            let page = SettingsPageCatalog.page("kbdlight")!
            #expect(page.featureID == "brightness", "the page opens with the brightness switch and status")
            #expect(!page.isComingSoon)
        }
    }

    @Test func theDisplayPagesRenderWhileTheFeatureIsOff() {
        PortHostFixture.isolated { _ in
            // The keyboard light page is not rendered here: its body asks CoreBrightness whether a backlight exists.
            let r = rig(switchedOn: false)
            defer { r.cleanup() }
            for ported in r.binding.pages {
                let host = NSHostingView(rootView: ported.body())
                host.frame = NSRect(x: 0, y: 0, width: 720, height: 900)
                host.layoutSubtreeIfNeeded()
                #expect(host.fittingSize.height > 40, "\(ported.pageID) rendered \(host.fittingSize): empty while the feature is off")
            }
        }
    }

    // MARK: Source contract (read from the files, nothing runs)

    private static let services = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Sources/PortKit")

    private func displayFiles() throws -> [(name: String, text: String)] {
        let roots = ["Services/Display", "Bridge"]
        var result: [(String, String)] = []
        for root in roots {
            let dir = Self.services.appendingPathComponent(root)
            for name in try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() where name.hasSuffix(".swift") {
                if root == "Bridge", !name.hasPrefix("Display") { continue }
                result.append(("\(root)/\(name)", try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)))
            }
        }
        return result
    }

    @Test func noDisplayFileCanPromptForAPermission() throws {
        let files = try displayFiles()
        #expect(files.count >= 10, "the scan found the display files")
        for file in files {
            for line in file.text.split(separator: "\n") where !line.drop(while: { $0 == " " }).hasPrefix("//") {
                for banned in PortPromptScrubTests.banned {
                    #expect(!line.contains(banned), "\(file.name): \(banned)")
                }
            }
        }
    }

    @Test func onlyTheServiceLoadsAPrivateSymbolAndTheLaneAddsNone() throws {
        for file in try displayFiles() where file.name != "Services/Display/BrightnessService.swift" {
            #expect(!file.text.contains("dlopen(") && !file.text.contains("dlsym(") && !file.text.contains("@_silgen_name"),
                    "\(file.name): a new private-symbol site must be reviewed and listed")
        }
        // The one private site is on the allowlist, and every private call in it is optional (fails closed).
        let service = try #require(try displayFiles().first { $0.name == "Services/Display/BrightnessService.swift" })
        #expect(service.text.contains("static let getBrightness: GetBrightnessFn?"))
        #expect(service.text.contains("init?()"), "the keyboard light bridge is failable")
        let allowlist = try String(contentsOf: Self.services.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/port/private-api-allowlist.txt"), encoding: .utf8)
        #expect(allowlist.contains("Services/Display/BrightnessService.swift"))
    }

    @Test func theGateAndTheJournalAreWiredIntoTheService() throws {
        let service = try #require(try displayFiles().first { $0.name == "Services/Display/BrightnessService.swift" }).text
        #expect(service.contains("DDCReports.allowsDDC(outcome: .writeOnly, trusted: trusted)"), "DDC writes are gated")
        #expect(service.contains("BrightnessSupport.safeSoftwareDimLevel(value)"), "every dim goes through the floor")
        #expect(service.contains("DisplayGammaJournal.note(dimmed: true)") && service.contains("DisplayGammaJournal.note(dimmed: false)"))
        let bridge = try String(contentsOf: Self.services.appendingPathComponent("Bridge/PortBridge.swift"), encoding: .utf8)
        #expect(bridge.contains("DisplayBrightnessLane.recoverAtLaunch(defaults: defaults)"), "launch recovery is wired")
    }
}
