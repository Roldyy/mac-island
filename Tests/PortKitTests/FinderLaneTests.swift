import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import PortKit
@testable import ShellKit

/// Lane W7A: the ported Finder engine (cut and paste, rename shortcut) REPLACES our tab's key tap, and the disk image
/// installer is a new feature. Bound through fake runtimes and a real `FeatureRegistry`: nothing here installs a tap,
/// mounts an image, scripts the Finder or touches a real file.
@MainActor
@Suite(.serialized) struct FinderLaneTests {
    final class Log {
        var events: [String] = []
        func count(_ event: String) -> Int { events.filter { $0 == event }.count }
    }

    struct Rig {
        let binding: PortFeatureBinding
        let registry: FeatureRegistry
        let log: Log
        let cleanup: () -> Void
    }

    func rig(finderOn: Bool = true, imageOn: Bool = false, accessibility: Bool = true) -> Rig {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        let log = Log()
        FinderLane.bind(into: binding, runtime: .init(sync: { log.events.append("finder.sync") },
                                                     stop: { log.events.append("finder.stop") }))
        DiskImageLane.bind(into: binding, runtime: .init(sync: { log.events.append("dmg.sync") },
                                                        stop: { log.events.append("dmg.stop") }))
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let probe = PermissionProbe(accessibility: { accessibility }, screenRecording: { true }, automation: { _ in nil })
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all + binding.descriptors, defaults: bench.defaults,
                                       crashMarker: marker, capabilityProvider: SystemCapabilities.provider(probe),
                                       withdraw: { _ in })
        registry.switches["finder"] = finderOn
        if imageOn { registry.switches["diskImageInstaller"] = true }
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        return Rig(binding: binding, registry: registry, log: log, cleanup: { bench.cleanup(); marker.clear() })
    }

    // MARK: Ids, descriptors

    @Test func theFinderIsOneRegistryFeatureAndTheBindingAddsNoDescriptorForIt() {
        let r = rig(finderOn: false)
        defer { r.cleanup() }
        #expect(AppFeature.finderCutPaste.registryID == "finder")
        #expect(AppFeature.finderRename.registryID == "finder", "folded into the one switch")
        #expect(PortFeatureIDs.existing["finderCutPaste"] == "finder")
        #expect(PortFeatureIDs.folded["finderRename"] == "finder")
        #expect(r.binding.descriptors.map(\.id) == ["diskImageInstaller"], "OUR finder descriptor is kept")
        #expect(r.registry.descriptors.filter { $0.id == "finder" }.count == 1)
        let finder = r.registry.descriptor("finder")
        #expect(finder?.tabID == "finder", "the island tab and the Home tile keep their id")
        #expect(finder?.permissions == [.accessibility, .automation])
        #expect(AppFeature.finderCutPaste.availabilityKey == "shell.enabled.finder")
        #expect(AppFeature.finderRename.availabilityKey == "shell.enabled.finder")
        #expect(r.log.events.isEmpty, "binding starts nothing")
    }

    @Test func theDiskImageInstallerIsANewFeatureOffUntilChosen() {
        let r = rig()
        defer { r.cleanup() }
        let d = r.registry.descriptor("diskImageInstaller")
        #expect(d != nil)
        #expect(AppFeature.diskImageInstaller.registryID == "diskImageInstaller")
        #expect(d?.title.isEmpty == false && d?.summary.isEmpty == false, "French title and summary from the catalog")
        #expect(d?.enabledByDefault == false)
        #expect(d?.risk == .touchesSystem)
        #expect(d?.tabID == nil)
        #expect(r.registry.state(for: "diskImageInstaller") == .off)
        #expect(r.log.events == ["finder.sync"], "only the Finder started; the installer waits for its switch")
    }

    // MARK: Start and stop

    @Test func theFinderStartsOnItsSwitchAndStopsWhenItGoesOff() {
        let r = rig()
        defer { r.cleanup() }
        #expect(r.log.count("finder.sync") == 1)
        #expect(r.binding.isStarted("finder"))
        #expect(r.binding.availability("finder") == true, "both services read the registry's verdict through this")
        r.registry.switches["finder"] = false
        #expect(r.log.count("finder.stop") == 1)
        #expect(r.binding.availability("finder") == false, "so each one removes its tap on its next sync")
        #expect(!r.binding.isStarted("finder"))
    }

    @Test func theFinderIsRestartedWhenAccessibilityArrives() {
        let r = rig(accessibility: false)
        defer { r.cleanup() }
        #expect(r.registry.state(for: "finder") == .needsPermission(.accessibility))
        // The registry still calls start; both services check Accessibility themselves and arm nothing without it
        // (`AXIsProcessTrusted()` in each sync), and nothing is asked.
        #expect(r.log.events == ["finder.sync"])
        let none = PermissionSnapshot(accessibility: false, inputMonitoring: true, screenRecording: true)
        let ax = PermissionSnapshot(accessibility: true, inputMonitoring: true, screenRecording: true)
        r.registry.permissionsChanged(PermissionChange(old: none, new: ax))
        #expect(r.log.events == ["finder.sync", "finder.stop", "finder.sync"], "re-armed once, by the registry")
    }

    @Test func bothServicesCheckAccessibilityThemselvesBeforeArmingATap() throws {
        for path in ["Sources/PortKit/Services/Finder/FinderCutPaste.swift",
                     "Sources/PortKit/Services/Finder/FinderRenameService.swift"] {
            let text = try Self.source(path)
            #expect(text.contains("accessibilityGranted: AXIsProcessTrusted()"), "\(path)")
        }
    }

    @Test func theInstallerStartsAndStopsWithItsSwitchOnly() {
        let r = rig(imageOn: true)
        defer { r.cleanup() }
        #expect(r.log.count("dmg.sync") == 1)
        r.registry.switches["diskImageInstaller"] = false
        #expect(r.log.count("dmg.stop") == 1)
        #expect(r.log.count("finder.stop") == 0, "the two features do not stop each other")
    }

    // MARK: Pages

    @Test func bothFinderPagesAreRealBodies() {
        FinderLane.bind(into: PortFeatureBinding(permissions: { PortPermissionState() }))
        for id in ["cutpaste", "renameshortcut"] {
            #expect(PortBridge.registeredPageIDs.contains(id), "\(id)")
            #expect(PortBridge.settingsBody(pageID: id) != nil, "\(id)")
        }
        #expect(SettingsLive.isEmpty(pageID: "cutpaste") && SettingsLive.isEmpty(pageID: "renameshortcut"),
                "a page the ported code draws whole shows no greyed copy of its rows")
        #expect(SettingsPageCatalog.page("cutpaste")?.featureID == "finder")
        #expect(SettingsPageCatalog.page("renameshortcut")?.featureID == "finder")
    }

    // MARK: The rename shortcut itself

    @Test func theRenameShortcutDefaultsToF2WithNoModifier() {
        #expect(GlobalShortcut.finderRenameDefault.keyCode == 120)
        #expect(GlobalShortcut.finderRenameDefault.modifiers.isEmpty)
        #expect(FeatureStrings.finderRename(.fr).hubTitle == "Raccourci pour renommer")
    }

    @Test func theKeyIsLeftAloneWhileTheFocusedItemIsATextField() {
        for role in ["AXTextField", "AXTextArea", "AXComboBox", "AXSecureTextField"] {
            #expect(!FinderRenameSupport.acceptsFocusedRole(role), "\(role)")
        }
        #expect(!FinderRenameSupport.acceptsFocusedRole(nil), "an unreadable focus is not touched")
        for role in ["AXOutline", "AXList", "AXScrollArea", "AXImage"] {
            #expect(FinderRenameSupport.acceptsFocusedRole(role), "\(role)")
        }
    }

    // MARK: Nothing from this lane prompts or drops a second tap

    @Test func aKeyPressNeverAsksForTheFinderAutomation() throws {
        let source = try Self.source("Sources/PortKit/Services/Finder/FinderCutPaste.swift")
        #expect(!source.contains("consentToAutomate("), "patch 1501: the click asks, a key press only reads")
        #expect(source.contains("finderAutomationGranted"))
    }

    @Test func theAppNoLongerStartsOurOwnFinderTapAndTheTabDefersToTheEngine() throws {
        let delegate = try Self.source("Sources/MacIsland/AppDelegate.swift")
        #expect(!delegate.contains("FinderFeature.start()"), "two engines on one key would move every file twice")
        #expect(!delegate.contains("FinderFeature.stop()"))
        #expect(delegate.contains("FinderFeature.engineStatus ="))
        #expect(delegate.contains("FinderFeature.engineSync ="))
        #expect(delegate.contains("FinderFeature.engineCancelCut ="))
    }

    @Test func theLanesPatchesAreNumberedInTheLanesRange() throws {
        let dir = PortSourceScrubTests.repoRoot.appendingPathComponent("scripts/port/patches")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".patch") }
        let lane = names.filter { name in (Int(name.prefix(4)) ?? 0) >= 1500 && (Int(name.prefix(4)) ?? 0) <= 1549 }
        #expect(Set(lane.map { String($0.prefix(4)) }) == ["1500", "1501", "1502"])
    }

    private static func source(_ relative: String) throws -> String {
        try String(contentsOf: PortSourceScrubTests.repoRoot.appendingPathComponent(relative), encoding: .utf8)
    }
}
