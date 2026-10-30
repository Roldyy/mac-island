import FanShared
import Foundation
import Testing

@Suite struct DaemonPlistTemplateTests {
    private var templateURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/Features/Fans/be.roldy.macisland.fanhelper.plist.template")
            .standardized
    }

    @Test func templateMatchesTheContractAndStaysOnDemand() throws {
        let data = try Data(contentsOf: templateURL)
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["Label"] as? String == FanHelperContract.machServiceName)
        #expect((plist["MachServices"] as? [String: Bool])?[FanHelperContract.machServiceName] == true)
        #expect(plist["BundleProgram"] as? String == "Contents/MacOS/FanHelper")
        #expect(plist["AssociatedBundleIdentifiers"] as? [String] == [FanHelperContract.appIdentifier])
        #expect(plist["RunAtLoad"] == nil)
        #expect(plist["KeepAlive"] == nil)
        #expect(plist["Program"] == nil)
        #expect(FanHelperContract.daemonPlistName == "be.roldy.macisland.fanhelper.plist")
    }
}
