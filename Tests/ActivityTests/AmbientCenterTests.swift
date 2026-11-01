import Foundation
import IslandTestSupport
import IslandUI
import Testing
@testable import IslandKit

/// Rotation driven by hand: `fire()` ends every pending sleep, so no test waits on a clock.
private final class ManualSleep: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Error>] = []
    private(set) var requested: [Duration] = []

    func sleep(_ duration: Duration) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            lock.lock(); waiters.append(c); requested.append(duration); lock.unlock()
        }
    }

    var pending: Int { lock.lock(); defer { lock.unlock() }; return waiters.count }

    func fire() {
        lock.lock(); let all = waiters; waiters = []; lock.unlock()
        all.forEach { $0.resume() }
    }
}

@MainActor
@Suite struct AmbientCenterTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private struct Rig {
        let center: AmbientCenter
        let activity: ActivityCenter
        let prefs: ClosedIslandPreferences
        let sleep: ManualSleep
        let cleanup: () -> Void
    }

    private func rig(notched: Bool = false, settings: ClosedIslandSettings = .standard) -> Rig {
        let (defaults, cleanup) = TestDefaults.make()
        settings.write(to: defaults)
        defaults.set(true, forKey: ClosedIslandKeys.migrated)
        let prefs = ClosedIslandPreferences(defaults: defaults)
        let activity = ActivityCenter()
        let sleep = ManualSleep()
        let now = t0
        let center = AmbientCenter(
            activity: activity, preferences: prefs, isNotched: notched, rotationInterval: .seconds(4),
            sleep: { try await sleep.sleep($0) }, now: { now })
        return Rig(center: center, activity: activity, prefs: prefs, sleep: sleep, cleanup: cleanup)
    }

    private func item(_ id: String, _ wing: AmbientWing = .trailing, channel: String? = nil) -> AmbientIndicator {
        AmbientIndicator(id: id, channel: channel ?? id, symbol: "circle", text: id, wing: wing)
    }

    private func settle() async {
        for _ in 0..<6 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(20))
    }

    // MARK: Posting

    @Test func startsEmpty() {
        let r = rig(); defer { r.cleanup() }
        #expect(r.center.content == .empty)
        #expect(r.center.widthProxy.layout == .empty)
    }

    @Test func postShowsWithdrawHidesAndRepostReplaces() {
        let r = rig(); defer { r.cleanup() }
        r.center.post(item("a"))
        #expect(r.center.content.all.map(\.id) == ["a"])
        var changed = item("a"); changed.text = "new"
        r.center.post(changed)
        #expect(r.center.content.all.first?.text == "new")
        r.center.withdraw(id: "a")
        #expect(r.center.content.isEmpty)
        r.center.withdraw(id: "never-posted")  // harmless
    }

    @Test func settingsChangesApplyAtOnce() {
        let r = rig(); defer { r.cleanup() }
        r.center.post(AmbientIndicator(id: "battery", channel: AmbientChannel.battery, symbol: "b", text: "82%"))
        #expect(r.center.content.all.count == 1)
        r.prefs.setEnabled(AmbientChannel.battery, false)
        #expect(r.center.content.isEmpty)
        r.prefs.setEnabled(AmbientChannel.battery, true)
        #expect(r.center.content.all.count == 1)
    }

    // MARK: The activity engine

    @Test func theActivityEnginesWinnersBecomeIndicators() {
        let r = rig(); defer { r.cleanup() }
        r.prefs.setEnabled(AmbientChannel.music, true)  // music is a choice in Settings, off by default
        r.activity.post(IslandActivity(
            id: "agents.music", source: "now-playing", priority: .music,
            trailing: CompactItem(symbol: "waveform", text: "Titre")))
        #expect(r.center.content.all.map(\.channel) == [AmbientChannel.music])
        r.activity.withdraw(id: "agents.music")
        #expect(r.center.content.isEmpty)
    }

    @Test func theClaudeSampleFeedsTheClock() {
        let r = rig(); defer { r.cleanup() }
        r.activity.post(IslandActivity(id: "claude.1", source: "claude", priority: .claudeWorking,
                                       leading: CompactItem(symbol: "sparkles", status: .info)))
        #expect(r.center.content.all.first?.clockSince == nil)
        r.center.setClaude(ClaudeWorkSample(id: "1", isWaiting: false, since: t0))
        #expect(r.center.content.all.first?.clockSince == t0)
    }

    @Test func theDotComesFromTheArbiter() {
        let r = rig(); defer { r.cleanup() }
        // Two alerts that want the leading wing: the loser becomes the edge dot.
        r.activity.post(IslandActivity(id: "a", source: "s", priority: .alert, leading: CompactItem(symbol: "x", status: .warning)))
        r.activity.post(IslandActivity(id: "b", source: "s", priority: .music, leading: CompactItem(symbol: "y", status: .danger), showsDot: true))
        #expect(r.center.content.dot == .danger)
    }

    // MARK: Rotation

    @Test func nothingRotatesWhenEverythingFits() async {
        let r = rig(); defer { r.cleanup() }
        r.center.post(item("a")); r.center.post(item("b"))
        await settle()
        #expect(r.sleep.pending == 0)
        #expect(!r.center.content.isRotating)
    }

    @Test func rotationAdvancesEveryIntervalAndStopsWhenItIsNoLongerNeeded() async {
        let r = rig(); defer { r.cleanup() }
        for id in ["t1", "t2", "t3"] { r.center.post(item(id)) }
        #expect(r.center.content.all.map(\.id) == ["t1", "t2"])
        #expect(r.center.content.isRotating)
        await settle()
        #expect(r.sleep.requested.first == .seconds(4))
        r.sleep.fire(); await settle()
        #expect(r.center.content.all.map(\.id) == ["t3"])
        r.sleep.fire(); await settle()
        #expect(r.center.content.all.map(\.id) == ["t1", "t2"])  // wraps
        r.center.withdraw(id: "t3")
        await settle()
        let pending = r.sleep.pending
        r.sleep.fire(); await settle()
        #expect(r.center.content.all.map(\.id) == ["t1", "t2"])
        #expect(!r.center.content.isRotating)
        #expect(pending <= 1)
    }

    @Test func rotationPausesWhileTheStripIsNotOnScreen() async {
        let r = rig(); defer { r.cleanup() }
        for id in ["t1", "t2", "t3"] { r.center.post(item(id)) }
        await settle()
        r.center.setVisible(false)
        r.sleep.fire(); await settle()
        #expect(r.center.content.all.map(\.id) == ["t1", "t2"])  // the open island does not spin the closed one
        r.center.setVisible(true)
        await settle()
        r.sleep.fire(); await settle()
        #expect(r.center.content.all.map(\.id) == ["t3"])
    }

    @Test func turningRotationOffInSettingsFreezesTheFirstPage() async {
        let r = rig(); defer { r.cleanup() }
        for id in ["t1", "t2", "t3"] { r.center.post(item(id)) }
        r.prefs.setRotates(false)
        await settle()
        #expect(r.center.content.all.map(\.id) == ["t1", "t2"])
        #expect(!r.center.content.isRotating)
    }

    // MARK: Width

    @Test func theWidthProxyAsksForTheExtentTheContentNeeds() {
        let r = rig(notched: true); defer { r.cleanup() }
        r.center.post(AmbientIndicator(id: "a", symbol: "x", text: "82%", wing: .trailing))
        let expected = AmbientMetrics.notchedExtent(r.center.content, now: t0)
        #expect(expected > 0)
        #expect(NotchGeometry.wingExtent(for: r.center.widthProxy.layout) >= expected)
        r.center.withdraw(id: "a")
        #expect(r.center.widthProxy.layout == .empty)
    }

    @Test func aPillWithFewIndicatorsDoesNotGrowAtAll() {
        let r = rig(notched: false); defer { r.cleanup() }
        r.center.post(AmbientIndicator(id: "limits", channel: AmbientChannel.limits, symbol: "sparkle", text: "58%", progress: 0.58, wing: .leading))
        r.center.post(AmbientIndicator(id: "battery", channel: AmbientChannel.battery, symbol: "battery.75percent", text: "82%", wing: .trailing))
        #expect(r.center.widthProxy.layout == .empty)
    }

    @Test func switchingScreenKindRecomputesTheWidth() {
        let r = rig(notched: false); defer { r.cleanup() }
        r.center.post(item("a"))
        #expect(r.center.widthProxy.layout == .empty)  // fits the pill
        r.center.isNotched = true
        #expect(r.center.widthProxy.layout != .empty)  // a wing needs room beside the notch
    }

    @Test func aNotchedWingTooNarrowDropsWholeElementsInsteadOfOverflowing() {
        let r = rig(notched: true); defer { r.cleanup() }
        for id in ["a", "b"] {
            r.center.post(AmbientIndicator(id: id, symbol: "x", text: "Mmmmmmmmmm", wing: .leading))
        }
        let width = NotchGeometry.baseWing + AmbientMetrics.notchedExtents(r.center.content, now: t0).leading
        let leading = r.center.content.leading
        // Never a bare icon: whatever stays has its value, and what stays fits.
        #expect(leading.allSatisfy { $0.isReadable })
        #expect(leading.isEmpty || AmbientMetrics.groupWidth(leading, now: t0) + 2 * AmbientMetrics.wingPadding <= width)
    }

    // MARK: Clock

    @Test func theClockAsksForAnotherMeasureWhenItNeedsAnotherDigitGroup() async {
        let r = rig(); defer { r.cleanup() }
        r.activity.post(IslandActivity(id: "claude.1", source: "claude", priority: .claudeWorking,
                                       leading: CompactItem(symbol: "sparkles", status: .info)))
        r.center.setClaude(ClaudeWorkSample(id: "1", isWaiting: false, since: t0.addingTimeInterval(-3000)))
        await settle()
        // One timer is armed for the 600 s left before the hour (plus a little).
        #expect(r.sleep.requested.contains { $0 > .seconds(600) && $0 < .seconds(601) })
    }
}
