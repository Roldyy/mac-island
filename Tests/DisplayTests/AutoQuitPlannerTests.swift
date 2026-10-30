import Testing
@testable import DisplayFeature

@Suite struct AutoQuitPlannerTests {
    let config = AutoQuitConfig(delay: 30 * 60, userExclusions: ["test.app9"], ownPID: 1)

    private func plan(_ apps: [AppSnapshot], last: [Int32: Double], now: Double = 60,
                      since: Double = 0, config: AutoQuitConfig? = nil) -> [Int32] {
        let lastActive = last.mapValues { at($0) }
        return AutoQuitPlanner.candidates(apps: apps, lastActive: lastActive, now: at(now),
                                          monitoringSince: at(since), config: config ?? self.config).map(\.pid)
    }

    @Test func idleRegularAppPastTheDelayIsACandidate() {
        #expect(plan([app(10)], last: [10: 0]) == [10])
    }

    @Test func notIdleLongEnoughIsKept() {
        #expect(plan([app(10)], last: [10: 40]) == [])
        #expect(plan([app(10)], last: [10: 30], now: 59.99) == [])
        #expect(plan([app(10)], last: [10: 30], now: 60) == [10])
    }

    @Test func appWithAVisibleWindowIsKept() {
        #expect(plan([app(10, windows: 1)], last: [10: 0]) == [])
    }

    @Test func hiddenAppIsKeptEvenWithoutCountedWindows() {
        var hidden = app(10)
        hidden.isHidden = true
        #expect(plan([hidden], last: [10: 0]) == [])
    }

    @Test func appWhoseOnlyWindowIsMinimizedOrElsewhereIsKept() {
        // Window counting no longer needs the window on screen: any state counts as one window.
        #expect(plan([app(10, windows: 1)], last: [10: 0]) == [])
    }

    @Test func frontmostAppIsKept() {
        #expect(plan([app(10, front: true)], last: [10: 0]) == [])
    }

    @Test func appPlayingAudioIsKept() {
        #expect(plan([app(10, audio: true)], last: [10: 0]) == [])
    }

    @Test func accessoryAndAgentAppsAreKept() {
        #expect(plan([app(10, regular: false)], last: [10: 0]) == [])
    }

    @Test func appWithoutBundleIDIsKept() {
        let a = AppSnapshot(pid: 10, bundleID: nil, name: "x", isRegular: true, isFrontmost: false,
                            isPlayingAudio: false, windowCount: 0)
        #expect(plan([a], last: [10: 0]) == [])
    }

    @Test func builtInExclusionsAreKept() {
        for id in ["com.apple.finder", "com.apple.dock", "com.apple.loginwindow", "com.apple.systemuiserver"] {
            #expect(plan([app(10, id)], last: [10: 0]) == [], "\(id)")
        }
    }

    @Test func userExclusionIsKept() {
        #expect(plan([app(9)], last: [9: 0]) == [])
    }

    @Test func ownProcessIsKept() {
        #expect(plan([app(1)], last: [1: 0]) == [])
    }

    @Test func unknownLastActiveIsKept() {
        #expect(plan([app(10)], last: [:]) == [])
    }

    @Test func nothingHappensBeforeOneFullIntervalOfMonitoring() {
        // Idle since 0 per tracker, but monitoring started at 20 min: wait until 50.
        #expect(plan([app(10)], last: [10: 0], now: 45, since: 20) == [])
        #expect(plan([app(10)], last: [10: 0], now: 50, since: 20) == [10])
    }

    @Test func resultIsSortedByPid() {
        #expect(plan([app(30), app(20), app(10)], last: [10: 0, 20: 0, 30: 0]) == [10, 20, 30])
    }

    @Test func builtInsAreCaseSensitiveExactIDs() {
        #expect(plan([app(10, "com.apple.finder.helper")], last: [10: 0]) == [10])
    }
}
