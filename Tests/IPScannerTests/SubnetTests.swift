import Testing
@testable import IPScannerFeature

@Suite struct SubnetTests {
    typealias F = Fixtures

    @Test func addressParsingIsStrict() {
        #expect(IPv4Address("192.168.1.1")?.value == 0xC0A8_0101)
        #expect(IPv4Address("0.0.0.0")?.value == 0)
        for bad in ["", "1.2.3", "1.2.3.4.5", "256.1.1.1", "01.2.3.4", "1.2.3.04", " 1.2.3.4", "1.2.3.4 ", "+1.2.3.4",
                    "-1.2.3.4", "1..3.4", "a.b.c.d", "1.2.3.4/24", "1.2.3.١", "1.2.3.4\n"] {
            #expect(IPv4Address(bad) == nil, Comment(rawValue: bad))
        }
        #expect(IPv4Address("10.0.0.255")?.description == "10.0.0.255")
    }

    @Test func localRangesAreOnlyRFC1918AndLinkLocal() {
        for ok in ["10.0.0.1", "10.255.255.255", "172.16.0.1", "172.31.255.254", "192.168.0.1", "169.254.10.10"] {
            #expect(F.ip(ok).isLocalScannable, Comment(rawValue: ok))
        }
        for no in ["8.8.8.8", "172.15.255.255", "172.32.0.1", "192.167.1.1", "192.169.1.1", "100.64.0.1", "127.0.0.1", "224.0.0.251",
                   "169.253.1.1", "11.0.0.1", "255.255.255.255", "0.0.0.0"] {
            #expect(!F.ip(no).isLocalScannable, Comment(rawValue: no))
        }
    }

    @Test func maskToRangeAndBoundaryHosts() throws {
        let s = try #require(IPv4Subnet(address: F.ip("192.168.1.77"), mask: F.ip("255.255.255.0")))
        #expect(s.network.description == "192.168.1.0")
        #expect(s.prefix == 24 && s.hostCount == 254)
        #expect(s.broadcast.description == "192.168.1.255")
        #expect(s.firstHost.description == "192.168.1.1" && s.lastHost.description == "192.168.1.254")
        #expect(!s.isHost(F.ip("192.168.1.0")), "network address")
        #expect(!s.isHost(F.ip("192.168.1.255")), "broadcast")
        #expect(s.isHost(F.ip("192.168.1.1")) && s.isHost(F.ip("192.168.1.254")))
        #expect(!s.isHost(F.ip("192.168.2.1")))
        let hosts = s.hosts()
        #expect(hosts.count == 254 && hosts.first == s.firstHost && hosts.last == s.lastHost)
        #expect(hosts == hosts.sorted())
    }

    @Test func twoSubnetsFromDifferentHostsAreEqual() {
        #expect(F.subnet("10.1.2.3/16") == F.subnet("10.1.200.9/16"))
        #expect(F.subnet("10.1.2.3/16").description == "10.1.0.0/16")
    }

    @Test func slash31HasTwoHostsAndSlash32One() {
        let p2p = F.subnet("192.168.5.6/31")
        #expect(p2p.hostCount == 2)
        #expect(p2p.hosts().map(\.description) == ["192.168.5.6", "192.168.5.7"])
        #expect(p2p.isHost(F.ip("192.168.5.6")) && p2p.isHost(F.ip("192.168.5.7")))
        let single = F.subnet("192.168.5.9/32")
        #expect(single.hostCount == 1)
        #expect(single.hosts().map(\.description) == ["192.168.5.9"])
        #expect(!single.isHost(F.ip("192.168.5.8")))
        #expect(F.subnet("192.168.5.8").prefix == 32, "a bare address is a /32")
    }

    @Test func slash30HasTwoUsableHosts() {
        let s = F.subnet("192.168.5.0/30")
        #expect(s.hostCount == 2)
        #expect(s.hosts().map(\.description) == ["192.168.5.1", "192.168.5.2"])
    }

    @Test func hostCountsOfTheLimits() {
        #expect(F.subnet("10.0.0.0/22").hostCount == 1022)
        #expect(F.subnet("10.0.0.0/21").hostCount == 2046)
        #expect(F.subnet("10.0.0.0/16").hostCount == 65_534)
        #expect(F.subnet("0.0.0.0/0").hostCount == 4_294_967_294)
    }

    @Test func nonContiguousMasksAreRefused() {
        #expect(IPv4Subnet(address: F.ip("10.0.0.1"), mask: F.ip("255.0.255.0")) == nil)
        #expect(IPv4Subnet(address: F.ip("10.0.0.1"), mask: F.ip("0.255.255.255")) == nil)
        #expect(IPv4Subnet(address: F.ip("10.0.0.1"), mask: F.ip("255.255.255.253")) == nil)
        #expect(IPv4Subnet(address: F.ip("10.0.0.1"), mask: F.ip("255.255.255.255"))?.prefix == 32)
        #expect(IPv4Subnet(address: F.ip("10.0.0.1"), mask: F.ip("0.0.0.0"))?.prefix == 0)
    }

    @Test func cidrParsingIsStrict() {
        #expect(IPv4Subnet(cidr: "192.168.1.0/24")?.prefix == 24)
        for bad in ["", "/24", "192.168.1.0/", "192.168.1.0/33", "192.168.1.0/-1", "192.168.1.0/2x", "192.168.1.0/24/1", "a/24", "192.168.1.0/ 24"] {
            #expect(IPv4Subnet(cidr: bad) == nil, Comment(rawValue: bad))
        }
    }

    @Test func containmentOfSubnets() {
        let lan = F.subnet("192.168.1.0/24")
        #expect(lan.contains(F.subnet("192.168.1.128/25")))
        #expect(lan.contains(lan))
        #expect(!lan.contains(F.subnet("192.168.0.0/23")), "bigger")
        #expect(!lan.contains(F.subnet("192.168.2.0/24")), "sibling")
        #expect(!lan.contains(F.subnet("10.0.0.0/8")))
    }
}
