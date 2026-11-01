import Foundation
import Testing
@testable import ShellKit

@Suite struct RoldyBrandTests {
    @Test func theWebsiteIsHttpsOnTheExactHost() {
        let url = RoldyBrand.websiteURL
        #expect(url.scheme == "https")
        #expect(url.host() == "www.roldymanagement.be")
        #expect(url.absoluteString == "https://www.roldymanagement.be")
    }

    @Test func theCreditLineKeepsItsDiaeresis() {
        #expect(RoldyBrand.creditLine == "Créé par Harold le Hardÿ de Beaulieu - Roldy Management")
        #expect(RoldyBrand.creditLine.contains("ÿ"))
    }

    @Test func noDonationLinkToAnotherAuthorRemains() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let support = try String(contentsOf: root.appendingPathComponent("Sources/ShellKit/Settings/SupportPage.swift"), encoding: .utf8)
        #expect(!support.localizedCaseInsensitiveContains("buymeacoffee"))
        #expect(!support.localizedCaseInsensitiveContains("Soutenir Vorssaint"))
    }
}
