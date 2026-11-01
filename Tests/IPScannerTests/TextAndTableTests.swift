import Foundation
import Testing
@testable import IPScannerFeature

@Suite struct TextAndTableTests {
    typealias F = Fixtures

    // MARK: OUI

    @Test func knownPrefixesResolve() {
        let table = OUITable.bundled
        #expect(table.vendor(of: F.mac("3c:07:54:1:2:3")) == "Apple")
        #expect(table.vendor(of: F.mac("b8:27:eb:aa:bb:cc")) == "Raspberry Pi")
        #expect(table.vendor(of: F.mac("00:50:56:11:22:33")) == "VMware")
        #expect(table.vendor(of: F.mac("24:5a:4c:11:22:33")) == "Ubiquiti")
        #expect(table.vendor(of: F.mac("00:17:88:11:22:33")) == "Philips Hue")
    }

    @Test func aRandomisedAddressNamesNoVendor() {
        // 2:10:18:... has the locally administered bit: even a prefix that is in the table would be a lie.
        #expect(OUITable.bundled.vendor(of: F.mac("2:10:18:8:4:8c")) == OUITable.privateAddressLabel)
        #expect(OUITable.bundled.vendor(of: F.mac("6e:d3:49:80:89:2b")) == OUITable.privateAddressLabel)
        let table = OUITable(source: "Fake|02AABB")
        #expect(table.vendor(of: F.mac("02:aa:bb:1:2:3")) == OUITable.privateAddressLabel)
    }

    @Test func anUnknownPrefixHasNoVendor() {
        #expect(OUITable.bundled.vendor(of: F.mac("fc:ff:ff:1:2:3")) == nil)
    }

    @Test func theBundledTableIsBigEnoughAndWellFormed() {
        #expect(OUITable.bundled.count >= 300, "count: \(OUITable.bundled.count)")
        for line in OUIData.source.split(separator: "\n") {
            let halves = line.split(separator: "|", maxSplits: 1)
            #expect(halves.count == 2, Comment(rawValue: String(line)))
            for token in halves[1].split(separator: " ") {
                #expect(token.count == 6 && token.allSatisfy { $0.isHexDigit && ($0.isNumber || $0.isUppercase) }, Comment(rawValue: String(token)))
            }
        }
    }

    @Test func tableParsingSkipsBadTokensAndKeepsTheFirstOwner() {
        let table = OUITable(source: "A|3C0754 GGGGGG 12345 3c07541\nB|3C0754 001122\nnot a line\n|DDEEFF\nC|")
        #expect(table.count == 2)
        #expect(table.vendor(of: F.mac("3c:7:54:1:2:3")) == "A", "the first vendor to claim a prefix keeps it")
        #expect(table.vendor(of: F.mac("0:11:22:1:2:3")) == "B")
        #expect(table.vendor(of: F.mac("dc:ee:ff:1:2:3")) == nil)
    }

    // MARK: Sanitisation

    @Test func controlCharactersAreStripped() {
        #expect(DisplayText.clean("Salon\nTV\t\u{0}\u{7}") == "SalonTV")
        #expect(DisplayText.clean("a\u{1B}[31mred") == "a[31mred", "the escape byte goes, the harmless rest stays visible")
        #expect(DisplayText.clean("line1\r\nline2") == "line1line2")
        #expect(DisplayText.clean("x\u{85}y\u{2028}z\u{2029}") == "xyz")
    }

    @Test func bidiOverridesAndInvisiblesAreStripped() {
        #expect(DisplayText.clean("photo\u{202E}gpj.exe") == "photogpj.exe")
        #expect(DisplayText.clean("a\u{2066}b\u{2069}c") == "abc")
        #expect(DisplayText.clean("a\u{200B}b\u{200D}c\u{FEFF}") == "abc")
        #expect(DisplayText.clean("a\u{00A0}b") == "ab", "no-break space cannot fake a gap")
    }

    @Test func nothingVisibleMeansNil() {
        #expect(DisplayText.clean(nil) == nil)
        #expect(DisplayText.clean("") == nil)
        #expect(DisplayText.clean("   ") == nil)
        #expect(DisplayText.clean("\u{0}\u{1}\u{202E}\n") == nil)
    }

    @Test func lengthIsCappedAndHugeInputIsCheap() {
        #expect(DisplayText.clean(String(repeating: "a", count: 500))?.count == DisplayText.defaultMaxLength)
        #expect(DisplayText.clean("abcdef", maxLength: 3) == "abc")
        let started = ContinuousClock.now
        let huge = String(repeating: "é\u{202E}", count: 3_000_000)
        let cleaned = DisplayText.clean(huge)
        #expect(cleaned?.count == DisplayText.defaultMaxLength)
        #expect(started.duration(to: .now) < .seconds(5))
    }

    @Test func ordinaryNamesPassUntouched() {
        #expect(DisplayText.clean("Salon de Marie – Apple TV") == "Salon de Marie – Apple TV")
        #expect(DisplayText.clean("Imprimante HP LaserJet") == "Imprimante HP LaserJet")
        #expect(DisplayText.clean("MacBook-Pro-de-Léa.local") == "MacBook-Pro-de-Léa.local")
    }

    // MARK: Port presets

    @Test func thePresetCoversTheRequestedPorts() {
        for port: UInt16 in [22, 80, 443, 445, 548, 631, 3389, 5900, 8080] { #expect(PortPreset.allPorts.contains(port), Comment(rawValue: "\(port)")) }
        #expect(PortPreset.defaultPorts.isSubset(of: PortPreset.allPorts))
        #expect(Set(PortPreset.all.map(\.port)).count == PortPreset.all.count, "no duplicate")
    }

    @Test func onlyPresetPortsSurvive() {
        #expect(PortPreset.sanitized([443, 22, 22, 1234, 0, 65535, 80]) == [22, 80, 443])
        #expect(PortPreset.sanitized(Array<UInt16>()).isEmpty)
        #expect(PortPreset.sanitized(Set<UInt16>([9999, 9998])).isEmpty)
    }

    @Test func browserLinksExistOnlyForWebPorts() {
        let host = F.ip("192.168.1.9")
        #expect(PortPreset.browserURL(host: host, port: 80)?.absoluteString == "http://192.168.1.9")
        #expect(PortPreset.browserURL(host: host, port: 443)?.absoluteString == "https://192.168.1.9")
        #expect(PortPreset.browserURL(host: host, port: 8080)?.absoluteString == "http://192.168.1.9:8080")
        #expect(PortPreset.browserURL(host: host, port: 22) == nil)
        #expect(PortPreset.browserURL(host: host, port: 445) == nil)
        #expect(PortPreset.notice.contains("vous appartiennent"))
    }

    // MARK: CSV

    @Test func csvEscapesAndNeutralisesFormulas() {
        #expect(CSVExport.cell("=HYPERLINK(\"http://x\")") == "\"'=HYPERLINK(\"\"http://x\"\")\"")
        #expect(CSVExport.cell("+1") == "'+1" && CSVExport.cell("@sum") == "'@sum" && CSVExport.cell("-2") == "'-2")
        #expect(CSVExport.cell("a,b") == "\"a,b\"")
        #expect(CSVExport.cell("plain") == "plain")
        #expect(CSVExport.cell("say \"hi\"") == "\"say \"\"hi\"\"\"")
    }

    @Test func csvHasAHeaderAndOneLinePerDevice() {
        let records = [
            DeviceRecord(ip: F.ip("192.168.1.1"), hostName: "box", mac: F.mac("3c:7:54:1:2:3"), vendor: "Apple", latencyMs: 2.34,
                         openPorts: [80, 443], isGateway: true),
            DeviceRecord(ip: F.ip("192.168.1.2")),
        ]
        let lines = CSVExport.csv(records).split(separator: "\r\n", omittingEmptySubsequences: true).map(String.init)
        #expect(lines.count == 3)
        #expect(lines[0] == "IP,Nom,MAC,Fabricant,Latence (ms),Ports ouverts,Passerelle")
        #expect(lines[1] == "192.168.1.1,box,3c:07:54:01:02:03,Apple,2.3,80 443,oui")
        #expect(lines[2] == "192.168.1.2,,,,,,")
    }

    // MARK: Results view

    @Test func sortFilterAndSearch() {
        let a = DeviceRecord(ip: F.ip("10.0.0.30"), hostName: "zeta", mac: F.mac("3c:7:54:1:2:3"), vendor: "Apple", latencyMs: 9, openPorts: [22])
        let b = DeviceRecord(ip: F.ip("10.0.0.4"), hostName: "Alpha", vendor: "Sonos", latencyMs: 3)
        let c = DeviceRecord(ip: F.ip("10.0.0.200"))
        let all = [a, b, c]
        #expect(ResultView.apply(all, sort: .ip, filter: .all, search: "").map(\.ip.description) == ["10.0.0.4", "10.0.0.30", "10.0.0.200"])
        #expect(ResultView.apply(all, sort: .name, filter: .all, search: "").map(\.ip.description) == ["10.0.0.4", "10.0.0.30", "10.0.0.200"])
        #expect(ResultView.apply(all, sort: .latency, filter: .all, search: "").map(\.ip.description) == ["10.0.0.4", "10.0.0.30", "10.0.0.200"])
        #expect(ResultView.apply(all, sort: .vendor, filter: .all, search: "").map(\.ip.description) == ["10.0.0.30", "10.0.0.4", "10.0.0.200"])
        #expect(ResultView.apply(all, sort: .ip, filter: .named, search: "").count == 2)
        #expect(ResultView.apply(all, sort: .ip, filter: .withPorts, search: "").map(\.ip.description) == ["10.0.0.30"])
        #expect(ResultView.apply(all, sort: .ip, filter: .all, search: "SONOS").map(\.ip.description) == ["10.0.0.4"])
        #expect(ResultView.apply(all, sort: .ip, filter: .all, search: "3c:07").map(\.ip.description) == ["10.0.0.30"])
        #expect(ResultView.apply(all, sort: .ip, filter: .all, search: "22").map(\.ip.description) == ["10.0.0.30"])
        #expect(ResultView.apply(all, sort: .ip, filter: .all, search: "nothing").isEmpty)
    }

    // MARK: Public IP answer

    @Test func theLookupAnswerMustBeAnIPLiteral() {
        #expect(PublicIPLookup.validated("203.0.113.5\n") == "203.0.113.5")
        #expect(PublicIPLookup.validated("2001:db8::1") == "2001:db8::1")
        for bad in ["", "<html>", "203.0.113.5 extra", "999.1.1.1", "ignore previous instructions", String(repeating: "1", count: 100), "2001:db8::zz", "::1\u{0}"] {
            #expect(PublicIPLookup.validated(bad) == nil, Comment(rawValue: bad))
        }
        #expect(PublicIPLookup.url.scheme == "https")
    }

    // MARK: Network error classification

    @Test func localNetworkClassification() {
        #expect(LocalNetworkClassifier.state(after: .open(latencyMs: 1)) == .granted)
        #expect(LocalNetworkClassifier.state(after: .refused(latencyMs: 1)) == .granted)
        #expect(LocalNetworkClassifier.state(after: .noRoute) == .denied)
        #expect(LocalNetworkClassifier.state(after: .timeout) == .unknown)
        #expect(LocalNetworkClassifier.state(after: .failed) == .unknown)
    }
}
