import Testing
@testable import IPScannerFeature

@Suite struct ScanPlannerTests {
    typealias F = Fixtures

    @Test func aLocalInterfaceYieldsItsHosts() throws {
        let targets = try ScanPlanner.plan(interface: F.subnet("192.168.1.0/24"))
        #expect(targets.count == 254)
        #expect(targets.first?.description == "192.168.1.1" && targets.last?.description == "192.168.1.254")
    }

    @Test func aNarrowerRangeInsideTheInterfaceIsAllowed() throws {
        let targets = try ScanPlanner.plan(interface: F.subnet("192.168.1.0/24"), requested: F.subnet("192.168.1.64/28"))
        #expect(targets.count == 14)
        #expect(targets.allSatisfy { F.subnet("192.168.1.64/28").contains($0) })
    }

    @Test func aPublicInterfaceIsRefused() {
        for cidr in ["8.8.8.0/24", "203.0.113.0/24", "172.32.0.0/24", "100.64.0.0/24"] {
            #expect(throws: ScanRefusal.interfaceNotLocal) { try ScanPlanner.plan(interface: F.subnet(cidr)) }
        }
    }

    @Test func aRequestOutsideTheInterfaceSubnetIsRefused() {
        let lan = F.subnet("192.168.1.0/24")
        for cidr in ["192.168.2.0/24", "10.0.0.0/24", "192.168.0.0/16", "8.8.8.0/24", "192.168.1.0/23", "0.0.0.0/0", "192.168.2.5/32"] {
            #expect(throws: ScanRefusal.outsideInterfaceSubnet, Comment(rawValue: cidr)) {
                try ScanPlanner.plan(interface: lan, requested: F.subnet(cidr))
            }
        }
    }

    @Test func aRangeThatStraddlesTheBroadcastEdgeIsRefused() {
        // A /23 whose first half is the LAN: not contained, so refused even though it overlaps.
        #expect(throws: ScanRefusal.outsideInterfaceSubnet) {
            try ScanPlanner.plan(interface: F.subnet("192.168.1.0/24"), requested: F.subnet("192.168.0.0/23"))
        }
    }

    @Test func aSlash22IsTheLimitWithoutConfirmation() throws {
        #expect(try ScanPlanner.plan(interface: F.subnet("10.0.0.0/22")).count == 1022)
        #expect(throws: ScanRefusal.needsConfirmation(hostCount: 2046)) { try ScanPlanner.plan(interface: F.subnet("10.0.0.0/21")) }
    }

    @Test func aLargerRangeNeedsConfirmationAndStopsAtSlash16() throws {
        #expect(try ScanPlanner.plan(interface: F.subnet("10.0.0.0/21"), confirmedLarge: true).count == 2046)
        #expect(try ScanPlanner.plan(interface: F.subnet("10.1.0.0/16"), confirmedLarge: true).count == 65_534)
        #expect(throws: ScanRefusal.tooLarge(hostCount: 131_070)) {
            try ScanPlanner.plan(interface: F.subnet("10.0.0.0/15"), confirmedLarge: true)
        }
        #expect(throws: ScanRefusal.tooLarge(hostCount: 16_777_214)) {
            try ScanPlanner.plan(interface: F.subnet("10.0.0.0/8"), confirmedLarge: true)
        }
    }

    @Test func aNarrowRangeInsideAHugeInterfaceStaysSmall() throws {
        let targets = try ScanPlanner.plan(interface: F.subnet("10.0.0.0/8"), requested: F.subnet("10.9.9.0/24"))
        #expect(targets.count == 254)
    }

    @Test func linkLocalIsScannable() throws {
        #expect(try ScanPlanner.plan(interface: F.subnet("169.254.0.0/24")).count == 254)
    }

    @Test func pointToPointRanges() throws {
        #expect(try ScanPlanner.plan(interface: F.subnet("192.168.7.4/31")).count == 2)
        #expect(try ScanPlanner.plan(interface: F.subnet("192.168.7.4/32")).count == 1)
    }

    @Test func aPortScanTargetMustBeARealLocalHost() throws {
        let subnets = [F.subnet("192.168.1.0/24")]
        try ScanPlanner.validateHost(F.ip("192.168.1.50"), in: subnets)
        for bad in ["192.168.1.0", "192.168.1.255", "192.168.2.50", "8.8.8.8", "127.0.0.1", "224.0.0.251", "10.0.0.1"] {
            #expect(throws: ScanRefusal.invalidHost, Comment(rawValue: bad)) { try ScanPlanner.validateHost(F.ip(bad), in: subnets) }
        }
        #expect(throws: ScanRefusal.invalidHost) { try ScanPlanner.validateHost(F.ip("192.168.1.50"), in: []) }
        // A public interface subnet never validates a host, even a host inside it.
        #expect(throws: ScanRefusal.invalidHost) { try ScanPlanner.validateHost(F.ip("8.8.8.8"), in: [F.subnet("8.8.8.0/24")]) }
    }

    @Test func everyRefusalHasAFrenchMessage() {
        let all: [ScanRefusal] = [.interfaceNotLocal, .outsideInterfaceSubnet, .needsConfirmation(hostCount: 5), .tooLarge(hostCount: 5),
                                  .invalidHost, .invalidRange, .noInterface, .featureOff, .alreadyRunning]
        for refusal in all { #expect(!refusal.message.isEmpty && !refusal.message.contains("Bientôt")) }
    }
}
