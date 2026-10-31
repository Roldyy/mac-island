import Foundation
import Testing
import IslandUI
@testable import IslandKit

/// Expiry driven by hand: `fire()` ends every pending sleep, so no test waits on a clock.
private final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Error>] = []

    func sleep(_ duration: Duration) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            lock.lock(); waiters.append(c); lock.unlock()
        }
    }

    func fire() {
        lock.lock(); let all = waiters; waiters = []; lock.unlock()
        all.forEach { $0.resume() }
    }
}

@MainActor
@Suite struct ActivityCenterTests {
    private func activity(_ id: String, source: String = "s", _ priority: ActivityPriority = .music) -> IslandActivity {
        IslandActivity(id: id, source: source, priority: priority,
                       leading: CompactItem(symbol: "music.note", text: id))
    }

    @Test func startsEmpty() {
        #expect(ActivityCenter().layout == .empty)
    }

    @Test func postPublishesAndWithdrawClears() {
        let center = ActivityCenter()
        center.post(activity("a"))
        #expect(center.layout.leading?.text == "a")
        center.withdraw(id: "a")
        #expect(center.layout == .empty)
    }

    @Test func withdrawingAnUnknownIdIsHarmless() {
        let center = ActivityCenter()
        center.post(activity("a"))
        center.withdraw(id: "nope")
        #expect(center.layout.leading?.text == "a")
    }

    @Test func postingTheSameIdReplaces() {
        let center = ActivityCenter()
        center.post(activity("a"))
        center.post(IslandActivity(id: "a", source: "s", priority: .alert,
                                   leading: CompactItem(symbol: "bell", text: "new")))
        #expect(center.layout.leading?.text == "new")
    }

    @Test func higherPriorityTakesTheWingAndLeavingRestoresTheOther() {
        let center = ActivityCenter()
        center.post(activity("m", .music))
        center.post(activity("c", .claudeWaiting))
        #expect(center.layout.leading?.text == "c")
        center.withdraw(id: "c")
        #expect(center.layout.leading?.text == "m")
    }

    @Test func withdrawAllRemovesOnlyThatSource() {
        let center = ActivityCenter()
        center.post(activity("a", source: "claude", .claudeWorking))
        center.post(activity("b", source: "claude", .claudeWaiting))
        center.post(activity("m", source: "music", .music))
        center.withdrawAll(source: "claude")
        #expect(center.layout.leading?.text == "m")
        center.withdrawAll(source: "absent")
        #expect(center.layout.leading?.text == "m")
    }

    @Test func expiryWithdrawsTheActivity() async {
        let clock = ManualClock()
        let center = ActivityCenter(sleep: { try await clock.sleep($0) })
        center.post(activity("a"), expiresAfter: .seconds(5))
        center.post(activity("keep", .ambient))
        #expect(center.layout.leading?.text == "a")
        await settle()
        clock.fire()
        await settle()
        #expect(center.layout.leading?.text == "keep")
    }

    @Test func repostingBeforeExpiryCancelsTheOldTimer() async {
        let center = ActivityCenter(sleep: { try await Task.sleep(for: $0) })
        center.post(activity("a"), expiresAfter: .milliseconds(10))
        center.post(activity("a"))  // no expiry this time
        try? await Task.sleep(for: .milliseconds(80))
        #expect(center.layout.leading?.text == "a")
    }

    @Test func realClockExpiryWorks() async {
        let center = ActivityCenter()
        center.post(activity("a"), expiresAfter: .milliseconds(30))
        for _ in 0..<100 where center.layout != .empty { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(center.layout == .empty)
    }

    /// Lets the expiry task reach its sleep before the test fires the clock.
    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(20))
    }
}
