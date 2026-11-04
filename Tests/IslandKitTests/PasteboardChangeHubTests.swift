import Foundation
import Testing
@testable import IslandKit

/// Lane 1 (perf): one shared pasteboard watcher. A fake scheduler and a counting reader prove how many timers run
/// and how many times the pasteboard is read, without ever touching NSPasteboard.
@MainActor
@Suite struct PasteboardChangeHubTests {
    @MainActor final class Rig {
        var count = 1
        private(set) var reads = 0
        private(set) var scheduled: [TimeInterval] = []
        private(set) var live = 0
        private var ticks: [Int: @MainActor () -> Void] = [:]
        private var lastIndex = -1
        var hold = false
        var held: [@MainActor (Int) -> Void] = []

        lazy var hub = PasteboardChangeHub(
            reader: { [unowned self] done in
                reads += 1
                if hold { held.append(done) } else { done(count) }
            },
            schedule: { [unowned self] interval, tick in
                scheduled.append(interval); live += 1
                lastIndex += 1
                let index = lastIndex
                ticks[index] = tick
                return { [unowned self] in live -= 1; ticks[index] = nil }
            })

        func tick() { ticks[lastIndex]?() }
    }

    @Test func noSubscriberNoTimer() {
        let rig = Rig()
        #expect(!rig.hub.isRunning && rig.live == 0 && rig.scheduled.isEmpty)
    }

    @Test func theHubStopsWhenTheLastSubscriberLeaves() {
        let rig = Rig()
        let a = rig.hub.subscribe(interval: 0.5) { _ in }
        let b = rig.hub.subscribe(interval: 1) { _ in }
        #expect(rig.hub.isRunning && rig.live == 1, "two subscribers share one timer")
        rig.hub.unsubscribe(a)
        #expect(rig.hub.isRunning, "one is still there")
        rig.hub.unsubscribe(b)
        #expect(!rig.hub.isRunning && rig.live == 0)
        rig.tick()
        #expect(rig.reads == 0, "a stopped hub reads nothing")
    }

    @Test func oneReadPerTickForNSubscribers() {
        let rig = Rig()
        var seen: [[Int]] = [[], [], [], []]
        for i in 0..<4 { rig.hub.subscribe(interval: 0.8) { seen[i].append($0) } }
        rig.count = 7
        rig.tick()
        rig.count = 8
        rig.tick()
        #expect(rig.reads == 2 && rig.hub.readCount == 2, "4 subscribers, 2 ticks: 2 reads, not 8")
        #expect(seen == Array(repeating: [7, 8], count: 4), "every subscriber got each count")
    }

    @Test func theTimerFollowsTheFastestSubscriber() {
        let rig = Rig()
        let slow = rig.hub.subscribe(interval: 1) { _ in }
        #expect(rig.scheduled == [1])
        let fast = rig.hub.subscribe(interval: 0.5) { _ in }
        #expect(rig.scheduled == [1, 0.5] && rig.live == 1, "rescheduled, the old timer is cancelled")
        rig.hub.unsubscribe(fast)
        #expect(rig.scheduled == [1, 0.5, 1] && rig.live == 1)
        rig.hub.unsubscribe(slow)
        #expect(rig.live == 0)
    }

    @Test func aReadStillInFlightSkipsTheTickInsteadOfPilingUp() {
        let rig = Rig()
        var got: [Int] = []
        rig.hub.subscribe(interval: 0.5) { got.append($0) }
        rig.hold = true
        rig.tick(); rig.tick(); rig.tick()
        #expect(rig.reads == 1, "a wedged pasteboard server gets one read, not three")
        rig.count = 3
        rig.held.removeFirst()(3)
        #expect(got == [3])
        rig.hold = false
        rig.tick()
        #expect(rig.reads == 2 && got == [3, 3])
    }

    @Test func aSubscriberLeavingDuringATickIsNotCalledAfterwards() {
        let rig = Rig()
        var calls = 0
        let token = rig.hub.subscribe(interval: 0.5) { _ in calls += 1 }
        rig.hub.unsubscribe(token)
        rig.tick()
        #expect(calls == 0)
    }
}
