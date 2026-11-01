import Foundation
import Testing
@testable import IPScannerFeature

@Suite struct ArpParserTests {
    typealias F = Fixtures

    /// A real `arp -an` capture shape (this machine, addresses kept).
    static let sample = """
    ? (169.254.169.254) at (incomplete) on en0 [ethernet]
    ? (192.168.0.1) at 2:10:18:8:4:8c on en0 ifscope [ethernet]
    ? (192.168.0.22) at 6e:d3:49:80:89:2b on en0 ifscope [ethernet]
    ? (192.168.0.200) at 8a:bc:4f:fb:b9:c1 on en0 ifscope permanent [ethernet]
    ? (192.168.0.255) at ff:ff:ff:ff:ff:ff on en0 ifscope [ethernet]
    ? (224.0.0.251) at 1:0:5e:0:0:fb on en0 ifscope permanent [ethernet]
    """

    @Test func parsesResolvedUnicastEntriesOnly() {
        let entries = ArpParser.parse(Self.sample)
        #expect(entries.map(\.ip.description) == ["192.168.0.1", "192.168.0.22", "192.168.0.200"])
        #expect(entries[0].mac.description == "02:10:18:08:04:8c", "octets printed without leading zeros are normalised")
        #expect(entries.allSatisfy { $0.interface == "en0" })
    }

    @Test func incompleteBroadcastAndMulticastAreDropped() {
        #expect(ArpParser.parse("? (10.0.0.9) at (incomplete) on en0 [ethernet]").isEmpty)
        #expect(ArpParser.parse("? (10.0.0.255) at ff:ff:ff:ff:ff:ff on en0 [ethernet]").isEmpty)
        #expect(ArpParser.parse("? (224.0.0.251) at 1:0:5e:0:0:fb on en0 [ethernet]").isEmpty)
        #expect(ArpParser.parse("? (10.0.0.9) at 0:0:0:0:0:0 on en0 [ethernet]").isEmpty)
    }

    @Test func hostileLinesAreDroppedNeverRepaired() {
        let hostile = [
            "? (999.1.1.1) at a:b:c:d:e:f on en0 [ethernet]",
            "? (10.0.0.1; rm -rf /) at a:b:c:d:e:f on en0 [ethernet]",
            "? (10.0.0.1) at a:b:c:d:e:f:11 on en0 [ethernet]",
            "? (10.0.0.1) at a:b:c:d:e on en0 [ethernet]",
            "? (10.0.0.1) at zz:b:c:d:e:f on en0 [ethernet]",
            "? (10.0.0.1) at 100:b:c:d:e:f on en0 [ethernet]",
            "? (10.0.0.1) at a:b:c:d:e:f on en0;reboot [ethernet]",
            "? (10.0.0.1) at a:b:c:d:e:f on $(id) [ethernet]",
            "? (10.0.0.1) at a:b:c:d:e:f on averyveryverylonginterfacename0 [ethernet]",
            "? (10.0.0.1) a:b:c:d:e:f on en0 [ethernet]",
            "? 10.0.0.1 at a:b:c:d:e:f on en0 [ethernet]",
            "? (010.0.0.1) at a:b:c:d:e:f on en0 [ethernet]",
            "evil\u{0}name (10.0.0.1) at a:b:c:d:e:f on en0 [ethernet]",
            "? (10.0.0.1) at a:b:c:d:e:f",
            "at on",
            "",
            "\u{1B}[2J? (10.0.0.1) at a:b:c:d:e:f on en0",
        ]
        for line in hostile { #expect(ArpParser.parse(line).isEmpty, Comment(rawValue: line)) }
    }

    @Test func aNameColumnOtherThanQuestionMarkIsRefused() {
        // `arp -an` prints "?" there. Anything else is not an arp line, whatever it holds.
        #expect(ArpParser.parse("router\u{7} (10.0.0.7) at a:b:c:d:e:f on en0 ifscope [ethernet]").isEmpty)
        #expect(ArpParser.parse("?? (10.0.0.7) at a:b:c:d:e:f on en0 [ethernet]").isEmpty)
        #expect(ArpParser.parse("? (10.0.0.7) at a:b:c:d:e:f on en0 ifscope [ethernet]\n").count == 1)
    }

    @Test func aGiantLineIsSkippedAndTheNextOneStillParses() {
        let giant = "? (10.0.0.1) at a:b:c:d:e:f on en0 " + String(repeating: "x", count: 100_000)
        let entries = ArpParser.parse(giant + "\n? (10.0.0.2) at a:b:c:d:e:f on en0 [ethernet]\n")
        #expect(entries.map(\.ip.description) == ["10.0.0.2"])
    }

    @Test func linesAreBounded() {
        var text = ""
        for index in 0..<5000 { text += "? (10.0.\(index / 250).\(index % 250 + 1)) at a:b:c:d:e:f on en0 [ethernet]\n" }
        let entries = ArpParser.parse(text)
        #expect(entries.count == ArpParser.maxLines)
    }

    @Test func inputIsCutAtTheByteBound() {
        var data = Data(repeating: 0x0A, count: ArpParser.maxBytes)
        data.append(Data("? (10.0.0.1) at a:b:c:d:e:f on en0 [ethernet]\n".utf8))
        #expect(ArpParser.parse(data).isEmpty, "the only entry sits after the cap")
    }

    @Test func binaryGarbageAndInvalidUTF8DoNotCrash() {
        let garbage = Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
        _ = ArpParser.parse(garbage)
        var mixed = Data([0xFF, 0xFE, 0x0A])
        mixed.append(Data("? (10.0.0.1) at a:b:c:d:e:f on en0 [ethernet]\n".utf8))
        #expect(ArpParser.parse(mixed).count == 1)
        #expect(ArpParser.parse(Data()).isEmpty && ArpParser.parse("").isEmpty)
    }

    @Test func aDuplicateAddressKeepsTheFirstEntry() {
        let entries = ArpParser.parse("""
        ? (10.0.0.1) at a:b:c:d:e:f on en0 [ethernet]
        ? (10.0.0.1) at 1:2:3:4:5:6 on en1 [ethernet]
        """)
        #expect(entries.count == 1 && entries[0].mac.description == "0a:0b:0c:0d:0e:0f")
    }

    @Test func macParsing() {
        #expect(MACAddress("aa:bb:cc:dd:ee:ff")?.description == "aa:bb:cc:dd:ee:ff")
        #expect(MACAddress("AA:BB:CC:DD:EE:FF")?.ouiKey == "AABBCC")
        for bad in ["", "aa:bb:cc:dd:ee", "aa:bb:cc:dd:ee:ff:00", "aa-bb-cc-dd-ee-ff", "aa:bb:cc:dd:ee:fg", "aaa:bb:cc:dd:ee:ff", "::::::", " a:b:c:d:e:f"] {
            #expect(MACAddress(bad) == nil, Comment(rawValue: bad))
        }
        #expect(F.mac("2:10:18:8:4:8c").isLocallyAdministered)
        #expect(!F.mac("3c:7:54:1:2:3").isLocallyAdministered)
    }

    @Test func theTableReaderUsesAFixedProgramAndArguments() async {
        let runner = FakeRunner(output: Data(Self.sample.utf8))
        let entries = await ArpTableReader(runner: runner).read()
        #expect(entries.count == 3)
        #expect(runner.calls.count == 1)
        #expect(runner.calls[0].path == "/usr/sbin/arp")
        #expect(runner.calls[0].arguments == ["-an"])
        #expect(runner.calls[0].maxBytes == ArpParser.maxBytes)
        #expect(await ArpTableReader(runner: FakeRunner(output: nil)).read().isEmpty, "a failed run is an empty table")
    }
}
