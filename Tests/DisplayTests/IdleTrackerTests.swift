import Testing
@testable import DisplayFeature

@Suite struct IdleTrackerTests {
    @Test func firstSightingStartsTheClock() {
        var tracker = IdleTracker()
        tracker.update([app(10)], now: at(5))
        #expect(tracker.lastActive[10] == at(5))
    }

    @Test func idleAppKeepsItsTimestamp() {
        var tracker = IdleTracker()
        tracker.update([app(10)], now: at(5))
        tracker.update([app(10)], now: at(25))
        #expect(tracker.lastActive[10] == at(5))
    }

    @Test func windowFrontmostOrAudioRefreshesTheClock() {
        var tracker = IdleTracker()
        tracker.update([app(10), app(11), app(12)], now: at(0))
        tracker.update([app(10, windows: 2), app(11, front: true), app(12, audio: true)], now: at(10))
        #expect(tracker.lastActive[10] == at(10))
        #expect(tracker.lastActive[11] == at(10))
        #expect(tracker.lastActive[12] == at(10))
    }

    @Test func goneAppsAreForgotten() {
        var tracker = IdleTracker()
        tracker.update([app(10), app(11)], now: at(0))
        tracker.update([app(11)], now: at(1))
        #expect(tracker.lastActive[10] == nil)
        #expect(tracker.lastActive[11] != nil)
    }
}
