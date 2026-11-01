import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import PortKit
@testable import ShellKit

/// Lane W6-D: Kill Process and the port manager bound through `PortFeatureBinding` with a FAKE runtime and a real
/// `FeatureRegistry`. Nothing here lists a process, runs `lsof` or sends a signal.
@MainActor
@Suite(.serialized) struct KillPortsLaneTests {
    static let kill = "killProcess"
    static let ports = "portManager"
    static let all = [kill, ports]

    final class FakeRuntime {
        var events: [String] = []
        func count(_ event: String) -> Int { events.filter { $0 == event }.count }
        var runtime: KillPortsLane.Runtime {
            KillPortsLane.Runtime(
                startKill: { [self] in events.append("kill.start") }, stopKill: { [self] in events.append("kill.stop") },
                startPorts: { [self] in events.append("ports.start") }, stopPorts: { [self] in events.append("ports.stop") })
        }
    }

    struct Rig {
        let binding: PortFeatureBinding
        let registry: FeatureRegistry
        let fake: FakeRuntime
        let cleanup: () -> Void
    }

    func rig(switchedOn: Bool = true) -> Rig {
        let binding = PortFeatureBinding(permissions: { PortPermissionState() })
        let fake = FakeRuntime()
        KillPortsLane.bind(into: binding, runtime: fake.runtime)
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let probe = PermissionProbe(accessibility: { false }, screenRecording: { false }, inputMonitoring: { false },
                                    automation: { _ in nil })
        let registry = FeatureRegistry(descriptors: binding.descriptors, defaults: bench.defaults, crashMarker: marker,
                                       capabilityProvider: SystemCapabilities.provider(probe), withdraw: { _ in })
        binding.connectAvailability()
        if switchedOn { for d in binding.descriptors { registry.switches[d.id] = true } }
        registry.launch(starters: binding.starters, stoppers: binding.stoppers)
        return Rig(binding: binding, registry: registry, fake: fake, cleanup: { bench.cleanup(); marker.clear() })
    }

    // MARK: Descriptors and pages

    @Test func theLaneBindsTwoDescriptorsOffByDefaultWithTheCatalogPermissionsAndRisk() {
        PortHostFixture.isolated { _ in
            let binding = PortFeatureBinding(permissions: { PortPermissionState() })
            KillPortsLane.bind(into: binding, runtime: FakeRuntime().runtime)
            #expect(binding.descriptors.map(\.id) == Self.all)
            let table: [String: FeatureRisk] = [Self.kill: .touchesSystem, Self.ports: .safe]
            for d in binding.descriptors {
                #expect(d.permissions.isEmpty, "\(d.id) needs no system permission")
                #expect(d.risk == table[d.id], "\(d.id)")
                #expect(!d.enabledByDefault, "\(d.id) is never on by default")
                #expect(!d.title.isEmpty && !d.summary.isEmpty, "\(d.id) has French text from the hub strings")
            }
            KillPortsLane.bind(into: binding, runtime: FakeRuntime().runtime)
            #expect(binding.descriptors.count == 2, "a second bind adds nothing")
        }
    }

    @Test func eachFeatureBringsOnePageBodyOnAPageOfTheCatalogWithoutAnyGreyedRow() {
        PortHostFixture.isolated { _ in
            let binding = PortFeatureBinding(permissions: { PortPermissionState() })
            KillPortsLane.bind(into: binding, runtime: FakeRuntime().runtime)
            let pages = Dictionary(uniqueKeysWithValues: binding.pages.map { ($0.featureID, $0.pageID) })
            #expect(pages == [Self.kill: "forcequit", Self.ports: "ports"])
            #expect(KillPortsLane.pageIDs == ["killProcess": "forcequit", "portManager": "ports"])
            for pageID in pages.values {
                #expect(SettingsPageCatalog.page(pageID) != nil, "\(pageID) is a page of ours")
                #expect(SettingsPageCatalog.page(pageID)?.featureID == nil,
                        "\(pageID): the binding adds the feature card, the catalog row carries none")
                #expect(SettingsLive.isEmpty(pageID: pageID), "\(pageID): the ported body draws the whole page")
            }
        }
    }

    @Test func theLaneIsInTheLaneListAndTheAppDelegateStartsNothingOfItsOwn() throws {
        let root = PortSourceScrubTests.repoRoot
        let lanes = try String(contentsOf: root.appendingPathComponent("Sources/PortKit/Bridge/PortLanes.swift"), encoding: .utf8)
        #expect(lanes.contains("KillPortsLane.bind(into:),"))
        let delegate = try String(contentsOf: root.appendingPathComponent("Sources/MacIsland/AppDelegate.swift"), encoding: .utf8)
        for service in ["KillProcessService", "PortManagerService"] {
            #expect(!delegate.contains(service), "\(service) is reached only through the ported pages")
        }
    }

    // MARK: Off by default, start, stop

    @Test func nothingRunsOnAFreshInstallAndBothAreAvailableOnlyWhileTheRegistryHasThemOn() {
        PortHostFixture.isolated { _ in
            let r = rig(switchedOn: false)
            defer { r.cleanup() }
            #expect(r.fake.events.isEmpty)
            for id in Self.all {
                #expect(r.registry.state(for: id) == .off, "\(id)")
                #expect(r.binding.availability(id) == false, "\(id)")
            }
        }
    }

    @Test func eachFeatureStartsOnceWithoutAnyGrantAndStopsOnce() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            #expect(r.fake.events.sorted() == ["kill.start", "ports.start"])
            for id in Self.all { #expect(r.registry.state(for: id) == .active, "\(id)") }
            r.fake.events.removeAll()
            r.registry.switches[Self.kill] = false
            #expect(r.fake.events == ["kill.stop"], "the ports list keeps running when only the kill feature goes")
            #expect(r.binding.availability(Self.ports) == true)
            r.registry.switches[Self.kill] = false
            #expect(r.fake.count("kill.stop") == 1)
            for id in Self.all { r.binding.starters[id]!() }
            let before = r.fake.events
            for id in Self.all { r.binding.starters[id]!() }
            #expect(r.fake.events == before, "a second start of a running feature reaches nothing")
        }
    }

    @Test func theKillSwitchAndSafeModeStopBothAndNoKillIsAvailableAfterwards() {
        PortHostFixture.isolated { _ in
            let r = rig()
            defer { r.cleanup() }
            PortHost.availability = { [binding = r.binding] in binding.availability($0) }
            #expect(AppFeature.killProcess.isAvailable && AppFeature.portManager.isAvailable)
            r.fake.events.removeAll()
            r.registry.killSwitch = true
            #expect(r.fake.events.sorted() == ["kill.stop", "ports.stop"])
            #expect(AppFeature.killProcess.isAvailable == false, "the ports page's kill buttons and the command bar rows go")
            r.fake.events.removeAll()
            r.registry.killSwitch = false
            #expect(r.fake.events.sorted() == ["kill.start", "ports.start"])
            r.fake.events.removeAll()
            r.registry.safeMode = true
            #expect(r.fake.events.sorted() == ["kill.stop", "ports.stop"])
            #expect(AppFeature.killProcess.isAvailable == false)
        }
    }

    // MARK: A switched-off Kill Process never signals anything

    @Test func everyKillPathEndsInOneGateAndOnlyWhenTheFeatureIsOn() throws {
        let root = PortSourceScrubTests.repoRoot
        let source = try String(contentsOf: root.appendingPathComponent("Sources/PortKit/Services/KillProcess/KillProcessService.swift"),
                                encoding: .utf8)
        // Patch 1401: `killBatch` is where every kill (row, name, tree, ports page, command bar) ends, and `restart`
        // has its own direct signal.
        let batch = try #require(source.range(of: "private func killBatch("))
        let afterBatch = source[batch.lowerBound...].prefix(700)
        #expect(afterBatch.contains("guard AppFeature.killProcess.isAvailable else { return [] }"))
        #expect(source.contains("guard AppFeature.killProcess.isAvailable, !entry.isProtected,"), "restart is gated too")
        // The only signal sites: the batch's direct kill, restart's direct kill, and the admin command inside the batch.
        let signalSites = source.components(separatedBy: "attemptDirectKill(target:").count - 1
        #expect(signalSites == 3, "definition + killBatch + restart, nothing else sends a signal: \(signalSites)")
    }

    @Test func thePortsPageOnlyKillsThroughTheKillServiceAndOnlyWhenKillProcessIsOn() throws {
        let root = PortSourceScrubTests.repoRoot
        let source = try String(contentsOf: root.appendingPathComponent("Sources/PortKit/Services/PortManager/PortManagerService.swift"),
                                encoding: .utf8)
        #expect(source.contains("guard AppFeature.killProcess.isAvailable, let startedAt = entry.startedAt else { return }"))
        #expect(source.contains("KillProcessService.shared.kill(pid:"))
        #expect(!source.contains("/bin/kill") && !source.contains("Darwin.kill"), "no signal of its own")
    }

    @Test func theLaneRunsNoCommandAndOpensNoPrompt() throws {
        let root = PortSourceScrubTests.repoRoot
        let source = try String(contentsOf: root.appendingPathComponent("Sources/PortKit/Bridge/KillPorts.swift"), encoding: .utf8)
        let code = source.split(separator: "\n").filter { !$0.drop(while: { $0 == " " }).hasPrefix("//") }.joined(separator: "\n")
        for banned in ["Shell.run", "Process(", "AdminShell", "requestAuthorization", "requestAccess", "UserDefaults.standard"] {
            #expect(!code.contains(banned), "\(banned)")
        }
    }
}
