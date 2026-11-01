import Foundation
import HIDEventSystem
import IslandKit
import IslandTestSupport
import Testing
@testable import PortKit
@testable import ShellKit

/// Lane W1B: the six mouse features bound through a fake runtime and a real `FeatureRegistry`. Nothing here
/// creates an event tap, touches a real pointing device or asks for a permission.
@MainActor
@Suite(.serialized) struct InputMouseTests {
    final class Log { var events: [String] = [] }

    struct Rig {
        let binding: PortFeatureBinding
        let registry: FeatureRegistry
        let log: Log
        let permissions: Box<PortPermissionState>
        let cleanup: () -> Void
    }

    static let ids = ["mouseAcceleration", "mouseNavigation", "mouseButtonShortcuts", "middleClick",
                      "mouseClickDebounce", "focusFollowsMouse"]

    func rig(granted: PortPermissionState = PortPermissionState(accessibility: true),
             middleClickReason: String? = nil, switchedOn: Bool = true) -> Rig {
        let permissions = Box(granted)
        let binding = PortFeatureBinding(permissions: { permissions.value })
        let log = Log()
        var hooks: [AppFeature: InputMouseRuntime.Hooks] = [:]
        for feature in InputMouseLane.features {
            let id = feature.registryID
            hooks[feature] = .init(start: { log.events.append("start \(id)") },
                                   stop: { log.events.append("stop \(id)") })
        }
        InputMouseLane.bind(into: binding, runtime: InputMouseRuntime(
            hooks: hooks, middleClickUnavailableReason: { middleClickReason }))
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let probe = PermissionProbe(accessibility: { permissions.value.accessibility },
                                    screenRecording: { permissions.value.screenRecording },
                                    inputMonitoring: { permissions.value.inputMonitoring }, automation: { _ in nil })
        let registry = FeatureRegistry(descriptors: binding.descriptors, defaults: bench.defaults, crashMarker: marker,
                                       capabilityProvider: SystemCapabilities.provider(probe), withdraw: { _ in })
        if switchedOn { for d in binding.descriptors { registry.switches[d.id] = true } }
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        return Rig(binding: binding, registry: registry, log: log, permissions: permissions,
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

    // MARK: Descriptors and pages

    @Test func sixDescriptorsPermissionsAndPagesMatchThePlan() {
        let r = rig(switchedOn: false)
        defer { r.cleanup() }
        #expect(Set(r.binding.descriptors.map(\.id)) == Set(Self.ids))
        for d in r.binding.descriptors {
            #expect(d.enabledByDefault == false, "\(d.id) is off by default")
            #expect(d.category == .input)
            if d.id == "mouseAcceleration" {
                #expect(d.permissions.isEmpty && d.risk == .touchesSystem)
            } else {
                #expect(d.permissions == [.accessibility] && d.risk == .touchesInput, "\(d.id)")
            }
            #expect(r.registry.state(for: d.id) == .off)
        }
        #expect(r.log.events.isEmpty, "binding starts nothing")
        let pages = Dictionary(uniqueKeysWithValues: r.binding.pages.map { ($0.featureID, $0.pageID) })
        #expect(pages == ["middleClick": "middleclick", "focusFollowsMouse": "focusfollows",
                          "mouseAcceleration": "noaccel", "mouseNavigation": "sidebuttons",
                          "mouseButtonShortcuts": "mouseshortcuts", "mouseClickDebounce": "clickfilter"])
        for page in r.binding.pages { #expect(SettingsPageCatalog.page(page.pageID) != nil, "\(page.pageID)") }
    }

    // MARK: Start, stop, permissions

    @Test func switchingOnStartsEachFeatureOnceAndOffStopsIt() {
        let r = rig(switchedOn: false)
        defer { r.cleanup() }
        r.registry.switches["mouseNavigation"] = true
        r.registry.switches["mouseNavigation"] = true
        #expect(r.log.events == ["start mouseNavigation"])
        r.registry.switches["mouseNavigation"] = false
        #expect(r.log.events == ["start mouseNavigation", "stop mouseNavigation"])
    }

    @Test func killSwitchStopsAllSixAndSafeModeKeepsNone() {
        let r = rig()
        defer { r.cleanup() }
        for id in Self.ids { #expect(r.log.events.contains("start \(id)"), "\(id)") }
        r.registry.killSwitch = true
        for id in Self.ids {
            #expect(r.log.events.contains("stop \(id)"), "kill switch stops \(id)")
            #expect(r.binding.availability(id) == false, "\(id) reads unavailable, so a page toggle cannot restart it")
        }
        r.log.events.removeAll()
        r.registry.killSwitch = false
        for id in Self.ids { #expect(r.log.events.contains("start \(id)"), "\(id)") }

        r.registry.safeMode = true
        for id in Self.ids { #expect(r.log.events.contains("stop \(id)"), "safe mode stops \(id)") }
    }

    @Test func accessibilityGatesFiveFeaturesButNeverAcceleration() {
        let r = rig(granted: PortPermissionState())
        defer { r.cleanup() }
        #expect(r.log.events == ["start mouseAcceleration"], "only acceleration needs no permission")
        change(r, to: PortPermissionState(accessibility: true))
        for id in Self.ids { #expect(r.log.events.filter { $0 == "start \(id)" }.count >= 1, "\(id)") }
        #expect(r.log.events.filter { $0 == "start mouseAcceleration" }.count == 1, "acceleration is not restarted")
        r.log.events.removeAll()
        change(r, to: PortPermissionState())
        #expect(!r.log.events.contains("stop mouseAcceleration"), "revoking Accessibility leaves acceleration alone")
        for id in Self.ids where id != "mouseAcceleration" { #expect(r.log.events.contains("stop \(id)"), "\(id)") }
    }

    // MARK: Private API

    @Test func middleClickProbeFailsClosed() {
        let r = rig(middleClickReason: "framework absent")
        defer { r.cleanup() }
        #expect(!r.log.events.contains("start middleClick"), "an unavailable framework never reaches the upstream start")
        #expect(r.log.events.contains("start mouseNavigation"))

        #expect(Multitouch.evaluate(frameworkLoaded: false, resolved: [:]) != nil)
        let missing = Multitouch.evaluate(frameworkLoaded: true, resolved: ["MTDeviceStart": false, "MTDeviceStop": true])
        #expect(missing?.contains("MTDeviceStart") == true)
        #expect(Multitouch.evaluate(frameworkLoaded: true, resolved: ["MTDeviceStart": true]) == nil)
        #expect((Multitouch.unavailableReason == nil) == Multitouch.available, "the live probe answers consistently")
    }

    // MARK: Acceleration recovery with a fake HID backend

    final class FakeMouse {
        var properties: [String: CFTypeRef]
        let registryID: UInt64
        var writes: [(String, Int64)] = []
        init(registryID: UInt64, acceleration: Int64) {
            self.registryID = registryID
            properties = ["HIDMouseAcceleration": acceleration as CFNumber, "VendorID": 1133 as CFNumber,
                          "ProductID": 49_000 as CFNumber, "LocationID": 7 as CFNumber, "Transport": "USB" as CFString]
        }
        var device: MouseAccelerationDevice {
            MouseAccelerationDevice(
                rawRegistryID: registryID, conformsToMouse: true,
                copyProperty: { [unowned self] in properties[$0] },
                setProperty: { [unowned self] key, value in
                    guard let number = value as? NSNumber else { return false }
                    writes.append((key, number.int64Value))
                    properties[key] = number
                    return true
                })
        }
        var acceleration: Int64 { (properties["HIDMouseAcceleration"] as? NSNumber)?.int64Value ?? .min }
    }

    private static let backendLock = NSRecursiveLock()

    private func withFakeBackend<T>(_ mice: [FakeMouse], guardStops: Box<Int>, _ body: (URL) throws -> T) rethrows -> T {
        Self.backendLock.lock()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mis-accel-\(UUID().uuidString)", isDirectory: true)
        let savedLister = MouseAccelerationRecovery.deviceLister
        let savedJournal = MouseAccelerationRecovery.journalURLOverride
        let savedLauncher = MouseAccelerationGuard.launcher
        MouseAccelerationRecovery.deviceLister = { _ in mice.map(\.device) }
        MouseAccelerationRecovery.journalURLOverride = dir.appendingPathComponent("journal.json")
        MouseAccelerationGuard.launcher = { MouseAccelerationGuard.Handle(onStop: { guardStops.value += 1; return true }) }
        defer {
            MouseAccelerationRecovery.deviceLister = savedLister
            MouseAccelerationRecovery.journalURLOverride = savedJournal
            MouseAccelerationGuard.launcher = savedLauncher
            try? FileManager.default.removeItem(at: dir)
            Self.backendLock.unlock()
        }
        return try body(dir)
    }

    /// What the service does on start, step by step: capture the original, journal it, apply the target.
    private func applyLinearMode(_ mouse: FakeMouse) -> Bool {
        let device = mouse.device
        guard var journal = MouseAccelerationRecovery.journalForMutation(),
              let id = MouseAccelerationRecovery.registryID(of: device),
              let identity = MouseAccelerationRecovery.identity(of: device),
              let entry = MouseAccelerationRecovery.captureEntry(for: device, registryID: id, identity: identity),
              MouseAccelerationRecovery.record(entry, in: &journal) else { return false }
        return MouseAccelerationRecovery.applyTarget(for: entry, to: device)
    }

    @Test func stopRestoresTheOriginalAccelerationAndEmptiesTheJournal() {
        let mouse = FakeMouse(registryID: 4242, acceleration: 45)
        let stops = Box(0)
        withFakeBackend([mouse], guardStops: stops) { dir in
            #expect(applyLinearMode(mouse))
            #expect(mouse.acceleration == -1, "acceleration is off while the feature runs")
            #expect(MouseAccelerationRecovery.hasPendingEntries(), "the journal holds the original")

            #expect(MouseAccelerationService.shared.stop(), "stop reports a complete restore")
            #expect(mouse.acceleration == 45, "the original value is back")
            #expect(!MouseAccelerationRecovery.hasPendingEntries())
            #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("journal.json").path))
        }
    }

    @Test func aJournalLeftByACrashIsRestoredAtLaunch() {
        let mouse = FakeMouse(registryID: 77, acceleration: 30)
        withFakeBackend([mouse], guardStops: Box(0)) { _ in
            #expect(applyLinearMode(mouse))
            #expect(mouse.acceleration == -1)
            // The app died here: the next launch calls the entry point PortBridge.recoverAtLaunch calls.
            MouseAccelerationService.recoverPendingAtLaunch()
            #expect(mouse.acceleration == 30)
            #expect(!MouseAccelerationRecovery.hasPendingEntries())
        }
    }

    @Test func aDeviceThatCannotBeRestoredKeepsItsJournalAndTheGuard() {
        let mouse = FakeMouse(registryID: 9, acceleration: 12)
        let stops = Box(0)
        withFakeBackend([mouse], guardStops: stops) { _ in
            #expect(applyLinearMode(mouse))
            let gone = FakeMouse(registryID: 1234, acceleration: 0)  // the listed device is not the journaled one
            gone.properties["ProductID"] = 1 as CFNumber  // a different product: not the same device re-enumerated
            MouseAccelerationRecovery.deviceLister = { _ in [gone.device] }
            #expect(!MouseAccelerationService.shared.stop(), "nothing could be restored, so stop says so")
            #expect(MouseAccelerationRecovery.hasPendingEntries(), "the journal stays for the next attempt")
            // The device comes back: the pending entry is restored, the guard handed over.
            MouseAccelerationRecovery.deviceLister = { _ in [mouse.device] }
            #expect(MouseAccelerationService.shared.stop())
            #expect(mouse.acceleration == 12)
            #expect(stops.value >= 1, "the guard child was told to finish")
        }
    }

    @Test func theCleanupFlagIsTheOneMainSwiftRunsBeforeAnyApp() throws {
        #expect(MouseAccelerationGuard.cleanupArgument == "--mouse-acceleration-cleanup")
        let main = try String(contentsOf: PortSourceScrubTests.repoRoot.appendingPathComponent("Sources/MacIsland/main.swift"),
                              encoding: .utf8)
        let flags = try #require(main.range(of: "PortBridge.runCleanupFlagsIfRequested()"))
        let app = try #require(main.range(of: "NSApplication.shared"))
        #expect(flags.lowerBound < app.lowerBound, "the re-exec'd cleanup exits before any NSApplication exists")
    }
}
