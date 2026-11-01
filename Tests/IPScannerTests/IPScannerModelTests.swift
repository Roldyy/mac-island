import Foundation
import IslandTestSupport
import Testing
@testable import IPScannerFeature

@MainActor
@Suite struct IPScannerModelTests {
    typealias F = Fixtures

    let bench = TestDefaults.make()

    func model(_ environment: IPScannerEnvironment) -> IPScannerModel {
        IPScannerModel(environment: environment, settings: IPScannerSettings(defaults: bench.defaults))
    }

    // MARK: Nothing happens by itself

    @Test func nothingRunsOnStartOrWhenTheViewAppears() async {
        defer { bench.cleanup() }
        let nudger = FakeNudger(), neighbors = FakeNeighbors(), fetcher = FakeFetcher(), checker = FakeChecker(), ports = FakePortProber()
        let m = model(F.environment(services: F.services(nudger: nudger, neighbors: neighbors), ports: ports, fetcher: fetcher, checker: checker))
        m.start()
        m.refreshInterfaces()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(m.scanState == .idle && m.devices.isEmpty)
        #expect(nudger.flight.started == 0 && neighbors.reads == 0 && ports.flight.started == 0)
        #expect(fetcher.urls.isEmpty, "the public IP is never fetched by default")
        #expect(checker.targets.isEmpty, "no local connection before the Autoriser click")
        #expect(m.publicIP == .notFetched && m.localNetwork == .unknown)
    }

    @Test func aFeatureThatIsNotStartedRefusesEveryAction() {
        defer { bench.cleanup() }
        let nudger = FakeNudger(), fetcher = FakeFetcher(), checker = FakeChecker()
        let m = model(F.environment(services: F.services(nudger: nudger), fetcher: fetcher, checker: checker))
        m.refreshInterfaces()
        #expect(m.interfaces.isEmpty, "inactive: not even the interfaces are read")
        m.startScan()
        m.fetchPublicIP()
        m.requestLocalNetworkAccess()
        #expect(m.scanState == .failed(ScanRefusal.featureOff.message))
        #expect(nudger.flight.started == 0 && fetcher.urls.isEmpty && checker.targets.isEmpty)
    }

    // MARK: Public IP

    @Test func thePublicIPIsFetchedOnClickWithOneRequestToTheVisibleURL() async {
        defer { bench.cleanup() }
        let fetcher = FakeFetcher(answer: "203.0.113.9\n")
        let m = model(F.environment(fetcher: fetcher))
        m.start()
        m.fetchPublicIP()
        #expect(await F.waitUntil { m.publicIP == .value("203.0.113.9") })
        #expect(fetcher.urls == [PublicIPLookup.url])
        m.fetchPublicIP()  // a second click is a second explicit request
        #expect(await F.waitUntil { fetcher.urls.count == 2 })
    }

    @Test func aHostileAnswerIsNeverShown() async {
        defer { bench.cleanup() }
        let m = model(F.environment(fetcher: FakeFetcher(answer: "<script>alert(1)</script>")))
        m.start()
        m.fetchPublicIP()
        #expect(await F.waitUntil { m.publicIP == .failed })
    }

    // MARK: Local network permission

    @Test func theAutoriserClickMakesTheFirstLocalConnectionToTheGateway() async {
        defer { bench.cleanup() }
        let checker = FakeChecker(state: .granted)
        let m = model(F.environment(checker: checker))
        m.start()
        m.refreshInterfaces()
        m.requestLocalNetworkAccess()
        #expect(await F.waitUntil { m.localNetwork == .granted })
        #expect(checker.targets == [F.ip("192.168.1.1")])
    }

    @Test func aDeniedAnswerIsKeptAndOffersThePane() async {
        defer { bench.cleanup() }
        let clip = Clip()
        let m = model(F.environment(checker: FakeChecker(state: .denied), clip: clip))
        m.start()
        m.refreshInterfaces()
        m.requestLocalNetworkAccess()
        #expect(await F.waitUntil { m.localNetwork == .denied })
        m.openLocalNetworkPane()
        #expect(clip.opened == [LocalNetworkPane.url])
        #expect(LocalNetworkPane.url.absoluteString.hasSuffix("Privacy_LocalNetwork"))
    }

    @Test func withoutAGatewayTheClickExplainsInsteadOfGuessing() {
        defer { bench.cleanup() }
        let checker = FakeChecker()
        let m = model(F.environment(interfaces: [F.interface(gateway: nil)], checker: checker))
        m.start()
        m.refreshInterfaces()
        m.requestLocalNetworkAccess()
        #expect(checker.targets.isEmpty && m.notice != nil)
    }

    // MARK: Scan

    @Test func aScanRunsOnClickAndListsTheDevices() async {
        defer { bench.cleanup() }
        let router = F.ip("192.168.1.1")
        let neighbors = FakeNeighbors([ArpEntry(ip: router, mac: F.mac("24:5a:4c:1:2:3"), interface: "en0")])
        let m = model(F.environment(services: F.services(nudger: FakeNudger(alive: [router]), neighbors: neighbors,
                                                         resolver: FakeResolver([router: "box"]))))
        m.start()
        m.refreshInterfaces()
        m.startScan()
        #expect(m.scanState.isScanning)
        #expect(await F.waitUntil { if case .finished = m.scanState { true } else { false } })
        #expect(m.devices.map(\.ip) == [router, F.ip("192.168.1.20")], "the router from ARP, then this Mac")
        #expect(m.devices.first?.displayName == "box" && m.devices.last?.isThisMac == true)
    }

    @Test func aRangeOverASlash22NeedsConfirmationAndSendsNothingBefore() async {
        defer { bench.cleanup() }
        let nudger = FakeNudger()
        let big = F.interface("10.0.0.5", cidr: "10.0.0.0/21", gateway: nil)
        let m = model(F.environment(interfaces: [big], services: F.services(nudger: nudger)))
        m.start()
        m.refreshInterfaces()
        m.startScan()
        #expect(m.pendingConfirmation == 2046 && m.scanState == .idle)
        #expect(nudger.flight.started == 0)
        m.dismissConfirmation()
        #expect(m.pendingConfirmation == nil)
        m.startScan()
        m.confirmPendingScan()
        #expect(await F.waitUntil { if case .finished = m.scanState { true } else { false } })
        #expect(nudger.flight.started == 2046)
        #expect(nudger.flight.peak <= 64)
    }

    @Test func aRangeOutsideTheSubnetOrAMalformedOneIsRefused() {
        defer { bench.cleanup() }
        let nudger = FakeNudger()
        let m = model(F.environment(services: F.services(nudger: nudger)))
        m.start()
        m.refreshInterfaces()
        for bad in ["10.0.0.0/24", "8.8.8.0/24", "192.168.0.0/16", "192.168.1.0/23"] {
            m.rangeText = bad
            m.startScan()
            #expect(m.scanState == .failed(ScanRefusal.outsideInterfaceSubnet.message), Comment(rawValue: bad))
        }
        for garbage in ["hello", "192.168.1.0/99", "192.168.1.0; rm -rf /"] {
            m.rangeText = garbage
            m.startScan()
            #expect(m.scanState == .failed(ScanRefusal.invalidRange.message), Comment(rawValue: garbage))
        }
        #expect(nudger.flight.started == 0)
    }

    @Test func aPublicInterfaceNeverScans() {
        defer { bench.cleanup() }
        let nudger = FakeNudger()
        let pub = LocalInterface(name: "en1", address: F.ip("203.0.113.7"), subnet: F.subnet("203.0.113.0/24"))
        let m = model(F.environment(interfaces: [pub], services: F.services(nudger: nudger)))
        m.start()
        m.refreshInterfaces()
        m.startScan()
        #expect(m.scanState == .failed(ScanRefusal.interfaceNotLocal.message) && nudger.flight.started == 0)
    }

    @Test func cancelStopsAScanInFlight() async {
        defer { bench.cleanup() }
        let nudger = FakeNudger(delay: .seconds(60))
        let neighbors = FakeNeighbors()
        let m = model(F.environment(services: F.services(nudger: nudger, neighbors: neighbors)))
        m.start()
        m.refreshInterfaces()
        m.startScan()
        #expect(await F.waitUntil { nudger.flight.started > 0 })
        m.cancelScan()
        #expect(await F.waitUntil(timeout: .seconds(10)) { m.scanState == .cancelled })
        #expect(neighbors.reads == 0)
    }

    @Test func stopCancelsEverythingAndForgetsTheResults() async {
        defer { bench.cleanup() }
        let router = F.ip("192.168.1.1")
        let m = model(F.environment(services: F.services(nudger: FakeNudger(alive: [router]),
                                                         neighbors: FakeNeighbors([ArpEntry(ip: router, mac: F.mac("24:5a:4c:1:2:3"), interface: "en0")]))))
        m.start()
        m.refreshInterfaces()
        m.startScan()
        #expect(await F.waitUntil { !m.devices.isEmpty })
        m.search = "x"
        m.stop()
        #expect(!m.isActive && m.devices.isEmpty && m.scanState == .idle && m.search.isEmpty && m.selectedHost == nil)

        // A scan in flight when the kill switch fires never publishes.
        let slow = FakeNudger(delay: .seconds(60))
        let m2 = model(F.environment(services: F.services(nudger: slow)))
        m2.start()
        m2.refreshInterfaces()
        m2.startScan()
        #expect(await F.waitUntil { slow.flight.started > 0 })
        m2.stop()
        try? await Task.sleep(for: .milliseconds(300))
        #expect(m2.devices.isEmpty && m2.scanState == .idle)
    }

    @Test func aSecondScanWhileOneRunsIsRefused() async {
        defer { bench.cleanup() }
        let slow = FakeNudger(delay: .seconds(60))
        let m = model(F.environment(services: F.services(nudger: slow)))
        m.start()
        m.refreshInterfaces()
        m.startScan()
        #expect(await F.waitUntil { slow.flight.started > 0 })
        let before = slow.flight.started
        m.startScan()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(m.scanState.isScanning && slow.flight.started == before)
        m.cancelScan()
    }

    // MARK: Port scan through the model

    @Test func thePortScanRunsOnClickOnAScannedHostOnly() async {
        defer { bench.cleanup() }
        let router = F.ip("192.168.1.1")
        let ports = FakePortProber(open: [80, 443])
        let m = model(F.environment(services: F.services(nudger: FakeNudger(alive: [router]),
                                                         neighbors: FakeNeighbors([ArpEntry(ip: router, mac: F.mac("24:5a:4c:1:2:3"), interface: "en0")])),
                                    ports: ports))
        m.start()
        m.refreshInterfaces()
        m.scanPorts(of: F.ip("8.8.8.8"))
        m.scanPorts(of: F.ip("192.168.2.2"))
        #expect(ports.flight.started == 0, "foreign hosts are refused before any packet")
        #expect(m.portScanState == .failed(ScanRefusal.invalidHost.message))
        m.startScan()
        #expect(await F.waitUntil { !m.devices.isEmpty })
        m.scanPorts(of: router)
        #expect(await F.waitUntil { if case .finished = m.portScanState { true } else { false } })
        #expect(m.devices.first?.openPorts == [80, 443])
        #expect(Set(ports.probed) == m.settings.ports, "only the user's chosen presets were probed")
    }

    // MARK: Results actions

    @Test func copyAndExportAreClicksOnTheVisibleResults() async {
        defer { bench.cleanup() }
        let clip = Clip()
        let router = F.ip("192.168.1.1")
        let m = model(F.environment(services: F.services(nudger: FakeNudger(alive: [router]),
                                                         neighbors: FakeNeighbors([ArpEntry(ip: router, mac: F.mac("24:5a:4c:1:2:3"), interface: "en0")])),
                                    clip: clip))
        m.start()
        m.refreshInterfaces()
        m.copyCSV()
        m.saveCSV()
        #expect(clip.copied.isEmpty && clip.saved.isEmpty, "nothing to export before a scan")
        m.startScan()
        #expect(await F.waitUntil { !m.devices.isEmpty })
        let record = m.devices[0]
        m.copyIP(record)
        m.copyMAC(record)
        m.copyCSV()
        m.saveCSV()
        #expect(clip.copied == ["192.168.1.1", "24:5a:4c:01:02:03", clip.copied[2]])
        #expect(clip.copied[2].hasPrefix("IP,Nom,MAC") && clip.copied[2].contains("192.168.1.1"))
        #expect(clip.saved.count == 1)
        m.openInBrowser(record, port: 80)
        #expect(clip.opened.isEmpty, "port 80 was not found open: no link")
    }

    @Test func settingsAreClampedAndPersistedAndNeverHoldResults() {
        defer { bench.cleanup() }
        let settings = IPScannerSettings(defaults: bench.defaults)
        #expect(settings.concurrency == 64 && settings.timeoutMs == 800 && settings.resolveNames && settings.useBonjour)
        #expect(settings.ports == PortPreset.defaultPorts)
        settings.concurrency = 100_000
        settings.timeoutMs = 1
        #expect(settings.concurrency == 128 && settings.timeoutMs == 200)
        settings.ports = [22, 4444, 80]
        #expect(settings.ports == [22, 80], "a port outside the presets cannot be selected")
        let again = IPScannerSettings(defaults: bench.defaults)
        #expect(again.concurrency == 128 && again.timeoutMs == 200 && again.ports == [22, 80], "4444 is not a preset")
        #expect(bench.defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("ipscanner.") }.allSatisfy {
            ["ipscanner.concurrency", "ipscanner.timeoutMs", "ipscanner.resolveNames", "ipscanner.bonjour", "ipscanner.ports"].contains($0)
        })
        again.resetToDefaults()
        #expect(again.concurrency == 64 && again.ports == PortPreset.defaultPorts)
    }
}
