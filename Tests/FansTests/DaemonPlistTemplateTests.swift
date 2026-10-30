import FanShared
import Foundation
import Testing

@Suite struct DaemonPlistTemplateTests {
    private var templateURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/Features/Fans/be.roldy.macisland.fanhelper.plist.template")
            .standardized
    }

    @Test func templateMatchesTheContract() throws {
        let data = try Data(contentsOf: templateURL)
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["Label"] as? String == FanHelperContract.machServiceName)
        #expect((plist["MachServices"] as? [String: Bool])?[FanHelperContract.machServiceName] == true)
        #expect(plist["BundleProgram"] as? String == "Contents/MacOS/FanHelper")
        #expect(plist["AssociatedBundleIdentifiers"] as? [String] == [FanHelperContract.appIdentifier])
        #expect(plist["Program"] == nil)
        #expect(FanHelperContract.daemonPlistName == "be.roldy.macisland.fanhelper.plist")
    }

    /// A crashed or SIGKILLed helper is relaunched by launchd (at most every 10 s) so its startup
    /// recovery puts the fans back to automatic without the app. A clean exit (0) is not restarted.
    @Test func launchdRelaunchesTheHelperAfterACrashOnly() throws {
        let data = try Data(contentsOf: templateURL)
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let keepAlive = try #require(plist["KeepAlive"] as? [String: Bool])
        #expect(keepAlive == ["SuccessfulExit": false])
        #expect(plist["ThrottleInterval"] as? Int == 10)
        #expect(plist["RunAtLoad"] == nil)   // implied by KeepAlive.SuccessfulExit, not set twice
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("no KeepAlive"))
    }
}
