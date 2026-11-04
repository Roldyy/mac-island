import Foundation
import Testing

/// The Wi-Fi name needs the Location permission: a usage string for the prompt and the hardened-runtime entitlement.
@Suite struct LocationResourcesTests {
    private static var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test func infoPlistCarriesBothFrenchLocationDescriptions() throws {
        let info = try #require(NSDictionary(contentsOf: Self.root.appendingPathComponent("Resources/Info.plist")))
        for key in ["NSLocationWhenInUseUsageDescription", "NSLocationUsageDescription"] {
            let text = try #require(info[key] as? String, "\(key) is missing")
            #expect(text.contains("nom du réseau Wi-Fi"), "\(key) names what is read")
            #expect(text.contains("Votre position n’est ni enregistrée ni envoyée."), "\(key) says nothing leaves")
        }
    }

    /// The signing tool's XML parser refuses a double hyphen inside a comment (the lenient Foundation parser does
    /// not), which once failed a whole release install at the signing step.
    @Test func noPlistCommentHoldsADoubleHyphen() throws {
        for file in ["Resources/MacIsland.entitlements", "Resources/Info.plist"] {
            let text = try String(contentsOf: Self.root.appendingPathComponent(file), encoding: .utf8)
            var rest = Substring(text)
            while let open = rest.range(of: "<!--") {
                let afterOpen = rest[open.upperBound...]
                let close = try #require(afterOpen.range(of: "-->"), "\(file): unterminated comment")
                #expect(!afterOpen[..<close.lowerBound].contains("--"), "\(file): '--' inside a comment")
                rest = afterOpen[close.upperBound...]
            }
        }
    }

    @Test func theEntitlementsAllowLocationAndKeepTheOthers() throws {
        let entitlements = try #require(NSDictionary(contentsOf: Self.root.appendingPathComponent("Resources/MacIsland.entitlements")))
        #expect(entitlements["com.apple.security.personal-information.location"] as? Bool == true)
        #expect(entitlements["com.apple.security.personal-information.calendars"] as? Bool == true, "the other keys stay")
        #expect(entitlements["com.apple.security.device.bluetooth"] as? Bool == true)
    }
}
