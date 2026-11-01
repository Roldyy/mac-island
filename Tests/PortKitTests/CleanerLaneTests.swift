import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import PortKit
@testable import ShellKit

/// Lane W7B: the ported cleaner (a new feature, off until chosen), bound through a fake runtime and a real
/// `FeatureRegistry`, and the guarantees it was bound under: preview first, Trash only, no hidden prompt. Nothing here
/// scans a real folder, trashes a file, asks for a permission or scripts the Finder.
@MainActor
@Suite(.serialized) struct CleanerLaneTests {
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

    func rig(on: Bool = false) -> Rig {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        let log = Log()
        CleanerLane.bind(into: binding, runtime: .init(sync: { log.events.append("sync") },
                                                      stop: { log.events.append("stop") }))
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let probe = PermissionProbe(accessibility: { true }, screenRecording: { true }, automation: { _ in nil })
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all + binding.descriptors, defaults: bench.defaults,
                                       crashMarker: marker, capabilityProvider: SystemCapabilities.provider(probe),
                                       withdraw: { _ in })
        if on { registry.switches["cleaner"] = true }
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        return Rig(binding: binding, registry: registry, log: log, cleanup: { bench.cleanup(); marker.clear() })
    }

    // MARK: Descriptor and switch

    @Test func theCleanerIsANewFeatureOffUntilChosen() {
        let r = rig()
        defer { r.cleanup() }
        let d = r.registry.descriptor("cleaner")
        #expect(d != nil)
        #expect(AppFeature.cleaner.registryID == "cleaner" && !PortFeatureIDs.isOwnedByExistingModule("cleaner"))
        #expect(d?.title.isEmpty == false && d?.summary.isEmpty == false, "French title and summary from the catalog")
        #expect(d?.enabledByDefault == false)
        #expect(d?.risk == .touchesSystem)
        #expect(d?.permissions.contains(.fullDiskAccess) == true)
        #expect(r.registry.state(for: "cleaner") == .off)
        #expect(r.log.events.isEmpty, "binding starts nothing, and a scan is never started by a switch")
    }

    @Test func theSwitchStartsAndStopsTheBackgroundServices() {
        let r = rig(on: true)
        defer { r.cleanup() }
        #expect(r.log.count("sync") == 1)
        #expect(r.binding.availability("cleaner") == true)
        r.registry.switches["cleaner"] = false
        #expect(r.log.count("stop") == 1)
        #expect(r.binding.availability("cleaner") == false, "the schedule and the WhatsApp tool read this and stop")
    }

    @Test func thePageIsARealBodyUnderTheCleanersCard() {
        CleanerLane.bind(into: PortFeatureBinding(permissions: { PortPermissionState() }))
        #expect(PortBridge.registeredPageIDs.contains("cleaner"))
        #expect(PortBridge.settingsBody(pageID: "cleaner") != nil)
        #expect(SettingsLive.isEmpty(pageID: "cleaner"))
        #expect(SettingsPageCatalog.page("cleaner")?.featureID == "cleaner")
    }

    // MARK: Preview first: pure policy, no folder is read

    @Test func onlyTheSafeGroupsStartChecked() {
        #expect(CleanerPolicy.precheckLoginItems && CleanerPolicy.precheckLogs && CleanerPolicy.precheckDeveloper)
        #expect(!CleanerPolicy.precheckLeftovers, "leftovers of an app are a judgment call: unchecked")
        #expect(!CleanerPolicy.precheckDeviceBackups, "an iPhone backup can be the only one: unchecked")
        #expect(!CleanerPolicy.precheckScreenshots, "a forgotten screenshot is the person's to pick: unchecked")
    }

    @Test func theScheduleIsOffUntilAFrequencyIsChosen() {
        #expect(CleanerSchedule.Frequency.sanitized("off") == .off)
        #expect(CleanerSchedule.Frequency.sanitized("") == .off, "no stored value: off")
        #expect(CleanerSchedule.Frequency.sanitized("nonsense") == .off, "an unreadable value never turns it on")
    }

    @Test func aProtectedBundleIsNeverAttributedToALeftover() {
        #expect(CleanerSupport.isProtectedBundleID("com.apple.finder"))
        #expect(!CleanerSupport.isAttributableBundleID("Library"), "a plain folder name proves nothing")
    }

    // MARK: Trash only, no hidden prompt: the sources this lane changed

    private static func lines(_ path: String) -> [Substring] {
        PortSourceScrubTests.files.first { $0.path == path }?.lines ?? []
    }

    private static func code(_ path: String) -> String {
        lines(path).filter { !$0.drop(while: { $0 == " " }).hasPrefix("//") }.joined(separator: "\n")
    }

    @Test func nothingInTheCleanerDeletesInPlace() {
        for path in ["Services/Cleaner/JunkCleaner.swift", "Services/Cleaner/CleanerScheduler.swift",
                     "Services/Cleaner/CleanerSupport.swift", "UI/Cleaner/CleanerView.swift"] {
            let text = Self.code(path)
            #expect(!text.isEmpty, "\(path) was not read")
            #expect(!text.contains(".removeItem("), "\(path): a removal in place")
            #expect(!text.contains("empty trash"), "\(path): the Trash is never emptied")
        }
        #expect(Self.code("Services/Cleaner/JunkCleaner.swift").contains("trashItem(at: item.url"), "the move to the Trash")
    }

    @Test func theTrashRowIsNotScannedAndEmptyingRefuses() {
        let text = Self.code("Services/Cleaner/JunkCleaner.swift")
        #expect(!text.contains("(.trash, { Self.scanTrash() })"), "patch 1502: the Trash is not offered")
        #expect(text.contains("private static func emptyTrash() -> Bool {\n        false"))
    }

    @Test func aRootOwnedItemIsNeverHandedToTheFinder() {
        #expect(!Self.code("UI/Cleaner/CleanerView.swift").contains("cleanSelected(escalate: true)"))
        #expect(Self.code("UI/Cleaner/CleanerView.swift").contains("cleanSelected(escalate: false)"))
        #expect(Self.code("Services/Cleaner/CleanerScheduler.swift").contains("cleanSelected(escalate: false)"),
                "the unattended pass never escalates either")
    }

    @Test func theFinderHelperReadsTheAutomationStateAndNeverAsks() {
        let text = Self.code("Services/Cleaner/JunkCleaner.swift")
        #expect(!text.contains("consentToAutomate("))
        #expect(text.contains("Permissions.automationStatus(for: .finder) == .granted"))
    }

    @Test func noScanStartsFromTheLaneItself() throws {
        let lane = try String(contentsOf: PortSourceScrubTests.repoRoot.appendingPathComponent("Sources/PortKit/Bridge/Cleaner.swift"),
                              encoding: .utf8)
        let code = lane.split(separator: "\n").filter { !$0.drop(while: { $0 == " " }).hasPrefix("//") }.joined(separator: "\n")
        #expect(!code.contains(".scan("), "a scan starts from the page's button only")
        #expect(!code.contains("cleanSelected"))
    }
}
