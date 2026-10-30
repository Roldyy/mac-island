import Foundation
import Testing
@testable import IslandKit

@Suite struct AppDefaultsTests {
    @Test func bundledAppUsesStandardDefaultsBecauseTheDomainIsTheSame() {
        // Inside the bundle `be.roldy.macisland`, a suite with that same name is invalid:
        // the standard domain already is that plist.
        let d = AppDefaults.make(bundleIdentifier: AppDefaults.identifier)
        #expect(d === UserDefaults.standard)
    }

    @Test func unbundledRunUsesTheNamedSuite() {
        let d = AppDefaults.make(bundleIdentifier: nil)
        #expect(d !== UserDefaults.standard)
        #expect(d != nil)
    }

    @Test func anotherBundleIdUsesTheNamedSuite() {
        let d = AppDefaults.make(bundleIdentifier: "com.example.other")
        #expect(d !== UserDefaults.standard)
    }
}
