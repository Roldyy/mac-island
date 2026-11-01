import FansFeature
import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import PortKit
@testable import ShellKit

/// Lane W6C: the fans bound through a fake runtime and a real `FeatureRegistry`, plus the source gates that keep the
/// ported policy off the SMC and off the helper's registration.
@MainActor
@Suite(.serialized) struct FansLaneTests {
    final class Log { var events: [String] = [] }

    struct Rig {
        let binding: PortFeatureBinding
        let registry: FeatureRegistry
        let log: Log
        let cleanup: () -> Void
    }

    func rig(runtime: FansLane.Runtime? = nil, log: Log = Log(), switchedOn: Bool = false) -> Rig {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        FansLane.bind(into: binding, runtime: runtime ?? FansLane.Runtime(
            start: { log.events.append("start") }, stop: { log.events.append("stop") }))
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let probe = PermissionProbe(accessibility: { true }, screenRecording: { true }, automation: { _ in nil })
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all + binding.descriptors, defaults: bench.defaults,
                                       crashMarker: marker, capabilityProvider: SystemCapabilities.provider(probe),
                                       withdraw: { _ in })
        registry.switches["fans"] = switchedOn
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        return Rig(binding: binding, registry: registry, log: log, cleanup: { bench.cleanup(); marker.clear() })
    }

    // MARK: Binding

    @Test func theFansAdoptOurSwitchAndAddNoDescriptor() {
        let r = rig()
        defer { r.cleanup() }
        #expect(r.binding.descriptors.isEmpty, "the registry keeps OUR fans descriptor")
        #expect(ShellDescriptors.all.filter { $0.id == "fans" }.count == 1)
        #expect(r.registry.descriptor("fans")?.risk == .privileged)
        #expect(r.binding.pages.isEmpty, "the page is a plain body: its catalog row already carries the feature card")
        #expect(r.log.events.isEmpty, "binding starts nothing")
        #expect(PortFeatureIDs.registryID(forUpstream: "fanControl") == "fans")
        #expect(AppFeature.fanControl.registryID == "fans")
    }

    @Test func onlyTheRegistrySwitchStartsAndStopsTheFans() {
        let r = rig()
        defer { r.cleanup() }
        r.registry.switches["fans"] = true
        r.registry.switches["fans"] = true
        #expect(r.log.events == ["start"], "idempotent")
        #expect(r.binding.availability("fans") == true)
        r.registry.switches["fans"] = false
        #expect(r.log.events == ["start", "stop"])
        #expect(r.binding.availability("fans") == false)
    }

    @Test func killSwitchAndSafeModeBothHandTheFansBack() {
        let r = rig(switchedOn: true)
        defer { r.cleanup() }
        #expect(r.log.events == ["start"])
        r.registry.killSwitch = true
        #expect(r.log.events == ["start", "stop"], "the kill switch stops the feature, whose stop hands the fans back")
        r.registry.killSwitch = false
        #expect(r.log.events == ["start", "stop", "start"])
        r.registry.safeMode = true
        #expect(r.log.events == ["start", "stop", "start", "stop"], "safe mode stops it too")
    }

    @Test func theRealStopOrderHandsBackBeforeTheModelDisconnects() {
        // The live runtime is not run here (it would build the real Fans model); its order is pinned in source.
        let source = FansSourceGates.text("Bridge/Fans.swift")
        guard let stop = source.range(of: "FanControlBackend.shared.stop()"),
              let model = source.range(of: "FansFeature.stop()") else {
            Issue.record("the live runtime must stop the policy and the Fans model")
            return
        }
        #expect(stop.lowerBound < model.lowerBound, "policy first, then the model's own automatic and disconnect")
        let start = FansSourceGates.text("Bridge/Fans.swift")
        #expect(start.contains("FansFeature.start()") && start.contains("FanControlBackend.shared.start()"))
    }

    @Test func aKillSwitchThroughTheRealBackendSendsAutomaticToTheDriver() async {
        let driver = FakeFanDriver()
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        let backend = FanControlBackend(environment: FanControlBackend.Environment(
            driver: { driver }, temperatures: { [FanControlTemperatureReading(source: .hottestSoC, celsius: 55)] },
            thermalState: { .nominal }, defaults: { bench.defaults }, tickInterval: 0.01, schedulesTicks: false))
        let r = rig(runtime: FansLane.Runtime(start: { backend.start() }, stop: { backend.stop() }), switchedOn: true)
        defer { r.cleanup() }
        await backend.applyConfigurationNow(.manual(level: 100))
        #expect(backend.isControlling && driver.isManualActive)
        r.registry.killSwitch = true
        #expect(driver.log.contains("autoNow"), "kill switch: the fans are handed back at once")
        #expect(!backend.isControlling && !driver.isManualActive)
        #expect(bench.defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded), "unconfirmed: the next launch hands back again")
    }

    // MARK: Page

    @Test func theFansPageIsAPlainBodyOfOurCatalogRow() {
        // Registered by the live wiring only; the id is the catalog's and carries no Bientot copy.
        #expect(FansLane.pageID == "fans")
        for line in FansSourceGates.text("Bridge/Fans.swift").split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
            #expect(!line.localizedCaseInsensitiveContains("bientôt") && !line.localizedCaseInsensitiveContains("bientot"))
        }
    }

    @Test func everyHandBackRuleTheSafetyCardPromisesHasACodePath() {
        #expect(FansPage.handBackRules.count == 5)
        let backend = FansSourceGates.text("Bridge/FanControlBackend.swift")
        for needle in ["func stop()", "func willSleep()", "willTerminateNotification", "temperatureFailures",
                       "returnAllToAutomaticNow()"] {
            #expect(backend.contains(needle), "\(needle)")
        }
        #expect(FansSourceGates.text("Bridge/FanControlEngine.swift").contains("serious"))
    }
}

/// Source gates on the fan lane, in the style of `PortSourceScrubTests`: the ported policy never writes the SMC, never
/// registers a daemon and never opens a second XPC connection. They fail on a re-import that brings upstream back.
@Suite struct FansSourceGates {
    static func text(_ path: String) -> String {
        (PortSourceScrubTests.files.first { $0.path == path }?.lines ?? []).joined(separator: "\n")
    }

    private static func code(_ path: String) -> [String] {
        text(path).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            .filter { !$0.drop(while: { $0 == " " }).hasPrefix("//") }
    }

    private static let policyFiles = ["Bridge/Fans.swift", "Bridge/FanControlBackend.swift", "Bridge/FanControlEngine.swift",
                                      "Services/FanControl/FanControlService.swift"]

    @Test func theLaneFilesExist() {
        for path in Self.policyFiles { #expect(!Self.text(path).isEmpty, "\(path)") }
    }

    @Test func noPolicyFileRegistersADaemonOpensXPCOrWritesTheSMC() {
        let forbidden = ["SMAppService", "NSXPCConnection", "NSXPCListener", "machServiceName", "startCooling",
                         "setTargetRPM", "writeManualPair", "SMCClient", "FanControlXPC", "FanControlIdentifiers",
                         "register()", "unregister("]
        for path in Self.policyFiles {
            for line in Self.code(path) {
                for word in forbidden {
                    #expect(!line.contains(word), "\(path): \(word) in `\(line.trimmingCharacters(in: .whitespaces))`")
                }
            }
        }
    }

    @Test func nothingOutsideTheHardwareFileCallsItsWriteMethods() {
        let writers = [".startCooling(", ".restoreAutomatic()", ".coolingIsIntact(", ".snapshot(isCooling"]
        var offenders: [String] = []
        for file in PortSourceScrubTests.files where file.path != "Services/FanControl/FanControlHardware.swift" {
            for (index, line) in file.lines.enumerated() {
                let trimmed = line.drop { $0 == " " || $0 == "\t" }
                if trimmed.hasPrefix("//") { continue }
                // `FanControlBackend.restoreAutomatic()` and the shim's own are not the hardware's.
                if line.contains("hardware") || line.contains("probe"), writers.contains(where: { line.contains($0) }) {
                    offenders.append("\(file.path):\(index + 1)")
                }
            }
        }
        #expect(offenders.isEmpty, "a hardware write path is reachable: \(offenders)")
    }

    @Test func theProbeOnlyReadsTemperatures() {
        let backend = Self.code("Bridge/FanControlBackend.swift").joined(separator: "\n")
        #expect(backend.contains("hardware?.readTemperatures()"))
        #expect(!backend.contains("hardware?.") || backend.components(separatedBy: "hardware?.").count == 2,
                "the probe has one use of the hardware: readTemperatures")
    }

    @Test func theShimKeepsTheSurfaceTheCardAndTheRecoveryRead() {
        let shim = Self.text("Services/FanControl/FanControlService.swift")
        for member in ["static let shared", "var accessState", "var snapshot", "var error", "var isWorking",
                       "static func recoverIfNeeded()", "func syncWithPreferences()", "func panelDidAppear()",
                       "func panelDidDisappear()", "func authorize()", "func applyConfiguration(",
                       "func returnToSystem()", "func resumePreferenceDidChange()", "func restoreAutomatic()"] {
            #expect(shim.contains(member), "\(member)")
        }
        #expect(PortSourceScrubTests.files.first { $0.path == "Services/FanControl/FanControlService.swift" }?.lines.count ?? 999 < 150,
                "a shim, not upstream's 690-line service")
    }

    @Test func theLaunchRecoveryStillGoesThroughTheShim() {
        let bridge = Self.text("Bridge/PortBridge.swift")
        #expect(bridge.contains("FanControlService.recoverIfNeeded()"))
        #expect(bridge.contains("if plan.fanControl"), "entered only when the journal is set")
    }
}
