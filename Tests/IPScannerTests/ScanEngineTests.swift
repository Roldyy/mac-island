import Foundation
import Testing
@testable import IPScannerFeature

@Suite struct ScanEngineTests {
    typealias F = Fixtures

    let lan = F.subnet("192.168.1.0/24")
    var context: ScanContext { ScanContext(subnet: lan, selfAddress: F.ip("192.168.1.20"), gateway: F.ip("192.168.1.1")) }

    @Test func nudgesStayWithinTheConcurrencyBound() async throws {
        let nudger = FakeNudger(delay: .milliseconds(5))
        var config = ScanConfiguration()
        config.concurrency = 16
        config.resolveNames = false
        config.useBonjour = false
        _ = try await ScanEngine.run(targets: lan.hosts(), context: context, configuration: config, services: F.services(nudger: nudger))
        #expect(nudger.flight.started == 254, "every target nudged exactly once")
        #expect(nudger.flight.peak <= 16, "peak \(nudger.flight.peak)")
        #expect(nudger.flight.peak >= 2, "the bound is a ceiling, not serial work")
    }

    @Test func theDefaultBoundIs64AndTheEngineClampsWhatItIsGiven() async throws {
        #expect(ScanConfiguration().concurrency == 64)
        var huge = ScanConfiguration()
        huge.concurrency = 10_000
        #expect(huge.clamped.concurrency == 128)
        huge.concurrency = 0
        #expect(huge.clamped.concurrency == 8)
        let nudger = FakeNudger(delay: .milliseconds(5))
        var config = ScanConfiguration()
        config.concurrency = 10_000
        config.resolveNames = false
        config.useBonjour = false
        _ = try await ScanEngine.run(targets: F.subnet("10.0.0.0/23").hosts(), context: ScanContext(subnet: F.subnet("10.0.0.0/23"), selfAddress: F.ip("10.0.0.5"), gateway: nil),
                                     configuration: config, services: F.services(nudger: nudger))
        #expect(nudger.flight.peak <= 128, "peak \(nudger.flight.peak)")
    }

    @Test func cancellationStopsTheScanBeforeTheTableIsRead() async {
        let nudger = FakeNudger(delay: .seconds(60))
        let neighbors = FakeNeighbors()
        let resolver = FakeResolver()
        let services = F.services(nudger: nudger, neighbors: neighbors, resolver: resolver)
        let context = self.context
        let targets = lan.hosts()
        let started = ContinuousClock.now
        let task = Task { try await ScanEngine.run(targets: targets, context: context, configuration: ScanConfiguration(), services: services) }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let result = await task.result
        if case .success = result { Issue.record("a cancelled scan must not finish") }
        if case .failure(let error) = result { #expect(error is CancellationError) }
        #expect(started.duration(to: .now) < .seconds(10), "the 60 s nudges were cancelled, not awaited")
        #expect(neighbors.reads == 0 && resolver.calls == 0)
        #expect(nudger.flight.started <= 64, "no more than the first window was ever started")
    }

    @Test func aScanCancelledBeforeItStartsDoesNothing() async {
        let nudger = FakeNudger()
        let services = F.services(nudger: nudger)
        let context = self.context
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ScanEngine.run(targets: [F.ip("192.168.1.9")], context: context, configuration: ScanConfiguration(), services: services)
        }
        let result = await task.result
        if case .success = result { Issue.record("must be cancelled") }
        #expect(nudger.flight.started == 0)
    }

    @Test func targetsOutsideTheInterfaceSubnetAreRefusedBeforeAnyPacket() async {
        let nudger = FakeNudger()
        let services = F.services(nudger: nudger)
        for outside in ["10.0.0.5", "192.168.2.5", "8.8.8.8", "224.0.0.251"] {
            await #expect(throws: ScanRefusal.outsideInterfaceSubnet, Comment(rawValue: outside)) {
                try await ScanEngine.run(targets: [F.ip("192.168.1.5"), F.ip(outside)], context: context, configuration: ScanConfiguration(), services: services)
            }
        }
        #expect(nudger.flight.started == 0)
    }

    @Test func aPublicInterfaceIsRefusedByTheEngineToo() async {
        let nudger = FakeNudger()
        let publicContext = ScanContext(subnet: F.subnet("8.8.8.0/24"), selfAddress: F.ip("8.8.8.8"), gateway: nil)
        await #expect(throws: ScanRefusal.interfaceNotLocal) {
            try await ScanEngine.run(targets: [F.ip("8.8.8.9")], context: publicContext, configuration: ScanConfiguration(), services: F.services(nudger: nudger))
        }
        #expect(nudger.flight.started == 0)
    }

    @Test func recordsAreAssembledFromArpNudgesNamesAndBonjour() async throws {
        let router = F.ip("192.168.1.1"), tv = F.ip("192.168.1.30"), me = F.ip("192.168.1.20"), quiet = F.ip("192.168.1.40")
        let neighbors = FakeNeighbors([
            ArpEntry(ip: router, mac: F.mac("24:5a:4c:1:2:3"), interface: "en0"),
            ArpEntry(ip: tv, mac: F.mac("2:10:18:8:4:8c"), interface: "en0"),
            ArpEntry(ip: F.ip("192.168.9.9"), mac: F.mac("3c:7:54:1:2:3"), interface: "en0"),  // not in the scanned range
        ])
        let resolver = FakeResolver([router: "box.home", tv: "Salon\u{202E}\nTV"])
        let discovery = FakeDiscovery(result: ServiceDiscovery(names: [tv: "AirPlay\u{0}Salon", quiet: "Imprimante", F.ip("192.168.9.9"): "ghost"]))
        let services = F.services(nudger: FakeNudger(alive: [router, me]), neighbors: neighbors, resolver: resolver, discovery: discovery)
        let found = try await ScanEngine.run(targets: lan.hosts(), context: context, configuration: ScanConfiguration(), services: services)
        let byIP = Dictionary(uniqueKeysWithValues: found.map { ($0.ip, $0) })
        #expect(Set(byIP.keys) == [router, tv, me], "out-of-range ARP rows and Bonjour names for absent hosts are dropped")
        #expect(byIP[router]?.isGateway == true && byIP[router]?.vendor == "Ubiquiti" && byIP[router]?.hostName == "box.home")
        #expect(byIP[router]?.latencyMs == 1.5)
        #expect(byIP[tv]?.hostName == "SalonTV", "name sanitised")
        #expect(byIP[tv]?.serviceName == "AirPlaySalon")
        #expect(byIP[tv]?.vendor == OUITable.privateAddressLabel)
        #expect(byIP[me]?.isThisMac == true && byIP[me]?.mac == nil && byIP[me]?.displayName == "Ce Mac")
        #expect(found == found.sorted { $0.ip < $1.ip })
    }

    @Test func namesAreNotLookedUpWhenTheSwitchIsOff() async throws {
        let resolver = FakeResolver()
        var config = ScanConfiguration()
        config.resolveNames = false
        let neighbors = FakeNeighbors([ArpEntry(ip: F.ip("192.168.1.1"), mac: F.mac("3c:7:54:1:2:3"), interface: "en0")])
        let found = try await ScanEngine.run(targets: lan.hosts(), context: context, configuration: config,
                                             services: F.services(neighbors: neighbors, resolver: resolver))
        #expect(resolver.calls == 0 && found.count == 2, "the router from ARP and this Mac")
    }

    @Test func progressIsReportedAndEndsComplete() async throws {
        final class Box: @unchecked Sendable {
            let lock = NSLock()
            var events: [ScanProgress] = []
            func add(_ p: ScanProgress) { lock.lock(); events.append(p); lock.unlock() }
        }
        let box = Box()
        var config = ScanConfiguration()
        config.useBonjour = false
        _ = try await ScanEngine.run(targets: lan.hosts(), context: context, configuration: config,
                                     services: F.services(nudger: FakeNudger(delay: .milliseconds(1)))) { box.add($0) }
        let probing = box.events.filter { $0.phase == .probing }
        #expect(probing.count == 254 && probing.last?.done == 254 && probing.last?.fraction == 1)
        #expect(box.events.contains { $0.phase == .readingTable })
    }

    // MARK: Port scan

    @Test func aPortScanRefusesAHostOutsideEveryActiveSubnet() async {
        let prober = FakePortProber(open: [80])
        for bad in ["8.8.8.8", "192.168.2.2", "127.0.0.1", "192.168.1.0", "192.168.1.255"] {
            await #expect(throws: ScanRefusal.invalidHost, Comment(rawValue: bad)) {
                try await PortScanEngine.run(host: F.ip(bad), ports: PortPreset.defaultPorts, subnets: [lan], prober: prober)
            }
        }
        #expect(prober.flight.started == 0)
    }

    @Test func aPortScanOnlyProbesPresetPortsOnce() async throws {
        let prober = FakePortProber(open: [22, 443])
        let config = PortScanConfiguration(minInterval: .zero)
        let open = try await PortScanEngine.run(host: F.ip("192.168.1.50"), ports: [443, 22, 22, 4444, 31337, 0], subnets: [lan],
                                                configuration: config, prober: prober)
        #expect(open == [22, 443])
        #expect(prober.probed.sorted() == [22, 443], "4444, 31337 and 0 are not presets and are never sent")
    }

    @Test func aPortScanIsBoundedAndRateLimited() async throws {
        let prober = FakePortProber(delay: .milliseconds(30))
        let config = PortScanConfiguration(concurrency: 2, minInterval: .milliseconds(20))
        let started = ContinuousClock.now
        _ = try await PortScanEngine.run(host: F.ip("192.168.1.50"), ports: PortPreset.allPorts, subnets: [lan], configuration: config, prober: prober)
        let elapsed = started.duration(to: .now)
        #expect(prober.flight.peak <= 2, "peak \(prober.flight.peak)")
        #expect(prober.flight.started == PortPreset.all.count)
        // 18 starts spaced by 20 ms cannot finish in under 17 gaps.
        #expect(elapsed >= .milliseconds(17 * 20 - 40), "elapsed \(elapsed)")
    }

    @Test func aPortScanCanBeCancelled() async {
        let prober = FakePortProber(delay: .seconds(60))
        let started = ContinuousClock.now
        let task = Task {
            try await PortScanEngine.run(host: F.ip("192.168.1.50"), ports: PortPreset.defaultPorts, subnets: [lan],
                                         configuration: PortScanConfiguration(minInterval: .zero), prober: prober)
        }
        try? await Task.sleep(for: .milliseconds(80))
        task.cancel()
        let result = await task.result
        if case .success = result { Issue.record("a cancelled port scan must not finish") }
        #expect(started.duration(to: .now) < .seconds(10))
    }

    @Test func anEmptyOrForeignPortListSendsNothing() async throws {
        let prober = FakePortProber()
        let open = try await PortScanEngine.run(host: F.ip("192.168.1.50"), ports: [UInt16(1), 2, 3], subnets: [lan], prober: prober)
        #expect(open.isEmpty && prober.flight.started == 0)
    }
}
