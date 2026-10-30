import Testing
@testable import DisplayFeature

@Suite struct AudioActivityTests {
    let apps: [Int32: String] = [100: "com.vendor.browser", 200: "com.vendor.player"]
    let known: Set<Int32> = [100, 200, 300]

    private func attribute(_ playing: [PlayingProcess], parents: [Int32: Int32] = [:]) -> AudioActivity.Attribution {
        AudioActivity.attribute(playing: playing, apps: apps, knownPIDs: known) { parents[$0] }
    }

    @Test func directlyPlayingAppIsAttributedToItself() {
        let result = attribute([PlayingProcess(pid: 200, bundleID: "com.vendor.player")])
        #expect(result == .init(appPIDs: [200], hasUnattributed: false))
    }

    @Test func helperChildIsAttributedToItsParentApp() {
        let result = attribute([PlayingProcess(pid: 500, bundleID: nil)], parents: [500: 450, 450: 100])
        #expect(result == .init(appPIDs: [100], hasUnattributed: false))
    }

    @Test func helperIsAttributedByBundlePrefixWhenTheTreeIsBroken() {
        // An XPC helper is parented to launchd, but its bundle id extends the app's.
        let result = attribute([PlayingProcess(pid: 500, bundleID: "com.vendor.browser.helper.audio")],
                               parents: [500: 1])
        #expect(result == .init(appPIDs: [100], hasUnattributed: false))
    }

    @Test func prefixMustEndAtADotBoundary() {
        let result = attribute([PlayingProcess(pid: 500, bundleID: "com.vendor.browserx")], parents: [500: 1])
        #expect(result.appPIDs.isEmpty)
        #expect(result.hasUnattributed)
    }

    @Test func unknownProcessIsFlaggedSoNobodyIsQuitBlindly() {
        let result = attribute([PlayingProcess(pid: 500, bundleID: "com.apple.unrelated")], parents: [500: 1])
        #expect(result == .init(appPIDs: [], hasUnattributed: true))
    }

    @Test func playingAgentAppIsKnownNotUnattributed() {
        let result = attribute([PlayingProcess(pid: 300, bundleID: "com.vendor.agent")])
        #expect(result == .init(appPIDs: [], hasUnattributed: false))
    }

    @Test func parentCycleTerminates() {
        let result = attribute([PlayingProcess(pid: 500, bundleID: nil)], parents: [500: 501, 501: 500])
        #expect(result.hasUnattributed)
    }
}
