import Foundation
import Testing
@testable import NowPlayingFeature

/// Lane 1 (perf): the AppleScript poll must not be a timer that runs for nothing. A fake clock records every
/// wait the model asks for, so "no timer scheduled" is asserted by an empty record, not by sleeping.
@MainActor
@Suite struct PollingEconomyTests {
    private let spotify = BundleIDs.spotify

    private func flags() -> MemoryFlags {
        let f = MemoryFlags()
        f.set(true, forKey: "nowplaying.automationRequested")
        return f
    }

    private func model(_ providers: [any NowPlayingProvider], running: Set<String>, clock: CountingClock,
                       lifecycle: FakeLifecycle? = nil, closedIndicatorWanted: Bool = true) -> NowPlayingModel {
        NowPlayingModel(providers: providers, defaults: flags(), interval: .seconds(1), transport: nil, artwork: nil,
                        running: StubRunning(ids: running), sleep: clock.sleep, lifecycle: lifecycle,
                        closedIndicatorWanted: closedIndicatorWanted)
    }

    // MARK: no player running, nothing polls

    @Test func noPlayerRunningSchedulesNoTimerAtAll() async {
        let clock = CountingClock()
        let p = FakeProvider(spotify, .success(nil))
        let m = model([p], running: [], clock: clock)
        m.setBackground(true)
        m.setHomeOpen(true)
        try? await Task.sleep(for: .milliseconds(120))
        #expect(clock.requested.get().isEmpty, "no player open: no wait is ever scheduled")
        m.setHomeOpen(false)
        m.setBackground(false)
    }

    @Test func aPlayerLaunchedLaterStartsThePollThroughTheLaunchNotification() async {
        let clock = CountingClock()
        let lifecycle = FakeLifecycle()
        let running = RunningSet()
        let p = FakeProvider(spotify, .success(snap(spotify, playing: true)))
        let m = NowPlayingModel(providers: [p], defaults: flags(), interval: .seconds(1), transport: nil, artwork: nil,
                                running: running, sleep: clock.sleep, lifecycle: lifecycle)
        m.setBackground(true)
        try? await Task.sleep(for: .milliseconds(60))
        #expect(clock.requested.get().isEmpty)
        #expect(lifecycle.started, "the model listens for launches instead of polling")
        running.set([spotify])
        lifecycle.fire()
        #expect(await eventually { clock.requested.get().count >= 2 })
        m.setBackground(false)
        #expect(lifecycle.stopped, "nobody needs the model: the observer goes too")
    }

    @Test func thePlayerQuittingEndsTheLoop() async {
        let clock = CountingClock()
        let lifecycle = FakeLifecycle()
        let running = RunningSet([spotify])
        let p = FakeProvider(spotify, .success(snap(spotify, playing: true)))
        let m = NowPlayingModel(providers: [p], defaults: flags(), interval: .seconds(1), transport: nil, artwork: nil,
                                running: running, sleep: clock.sleep, lifecycle: lifecycle)
        m.setBackground(true)
        #expect(await eventually { clock.requested.get().count >= 2 })
        running.set([])
        p.result.set(.success(nil))   // what the real provider answers for a player that is not open
        lifecycle.fire()
        try? await Task.sleep(for: .milliseconds(80))
        let n = clock.requested.get().count
        try? await Task.sleep(for: .milliseconds(80))
        #expect(clock.requested.get().count == n, "the player is gone: no more waits")
        #expect(m.snapshot == nil)
        m.setBackground(false)
    }

    // MARK: closed island

    @Test func closedWithoutAMusicIndicatorNothingPolls() async {
        let clock = CountingClock()
        let p = FakeProvider(spotify, .success(snap(spotify, playing: true)))
        let m = model([p], running: [spotify], clock: clock, closedIndicatorWanted: false)
        m.setBackground(true)
        try? await Task.sleep(for: .milliseconds(120))
        #expect(clock.requested.get().isEmpty && p.calls.get() == 0)
        m.setHomeOpen(true)
        #expect(await eventually { clock.requested.get().count >= 2 }, "the Home still polls while it is open")
        m.setHomeOpen(false)
        m.setBackground(false)
    }

    @Test func turningTheIndicatorOnStartsTheClosedPoll() async {
        let clock = CountingClock()
        let p = FakeProvider(spotify, .success(snap(spotify, playing: true)))
        let m = model([p], running: [spotify], clock: clock, closedIndicatorWanted: false)
        m.setBackground(true)
        try? await Task.sleep(for: .milliseconds(60))
        #expect(clock.requested.get().isEmpty)
        m.setClosedIndicatorWanted(true)
        #expect(await eventually { clock.requested.get().count >= 2 })
        #expect(Set(clock.requested.get()) == [.seconds(3)])
        m.setClosedIndicatorWanted(false)
        try? await Task.sleep(for: .milliseconds(60))
        let n = clock.requested.get().count
        try? await Task.sleep(for: .milliseconds(60))
        #expect(clock.requested.get().count == n)
        m.setBackground(false)
    }

    // MARK: the adapter is the single source of truth

    private func reading(_ title: String = "Reason", playing: Bool = true, bundle: String = BundleIDs.spotify,
                         position: TimeInterval = 10, duration: TimeInterval = 100) -> NowPlayingAdapterReading {
        NowPlayingAdapterReading(title: title, artist: "A", album: "Al", artworkData: Data(title.utf8), isPlaying: playing,
                                 position: position, duration: duration, rate: 1, sampledAt: Date(), bundleID: bundle)
    }

    @Test func anAdapterThatDeliversStopsTheAppleScriptPoll() async {
        let clock = CountingClock()
        let p = FakeProvider(spotify, .success(snap(spotify, title: "Script", playing: true)))
        let m = model([p], running: [spotify], clock: clock)
        m.setBackground(true)
        #expect(await eventually { p.calls.get() >= 2 }, "the fallback polls first")
        m.adapterDelivered(reading())
        try? await Task.sleep(for: .milliseconds(60))
        let calls = p.calls.get()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(p.calls.get() == calls, "adapter delivering: the AppleScript provider is not polled")
        #expect(m.snapshot?.title == "Reason" && m.artwork == Data("Reason".utf8))
        m.setHomeOpen(true)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(p.calls.get() == calls, "not even while the Home is open")
        m.setHomeOpen(false)
        m.setBackground(false)
    }

    @Test func anAdapterReadingNeedsNoAutomationPermission() async {
        let m = NowPlayingModel(providers: [], defaults: MemoryFlags(), interval: .seconds(1), transport: nil, artwork: nil)
        #expect(m.access == .needsAuthorization)
        m.adapterDelivered(reading())
        #expect(m.access == .ready && m.snapshot?.isPlaying == true)
        m.adapterUnavailable()
        #expect(m.access == .needsAuthorization && m.snapshot == nil, "back to what the stored flag says")
    }

    @Test func adapterNothingPlayingClearsTheTrackAndTellsTheClosedIsland() async {
        let m = NowPlayingModel(providers: [], defaults: flags(), interval: .seconds(1), transport: nil, artwork: nil)
        var seen: [String?] = []
        m.onSnapshot = { seen.append($0?.title) }
        m.adapterDelivered(reading())
        m.adapterDelivered(nil)
        #expect(seen == ["Reason", nil] && m.snapshot == nil)
    }

    @Test func theAdapterLeavingResumesTheAppleScriptFallback() async {
        let clock = CountingClock()
        let p = FakeProvider(spotify, .success(snap(spotify, title: "Script", playing: true)))
        let m = model([p], running: [spotify], clock: clock)
        m.setBackground(true)
        m.adapterDelivered(reading())
        try? await Task.sleep(for: .milliseconds(60))
        #expect(p.calls.get() == 0)
        m.adapterUnavailable()
        #expect(await eventually { m.snapshot?.title == "Script" })
        m.setBackground(false)
    }

    @Test func aPausedAdapterTrackSchedulesNoTimerAndAPlayingOneTicksOnlyWhileVisible() async {
        let clock = CountingClock()
        let m = model([], running: [spotify], clock: clock)
        m.setBackground(true)
        m.adapterDelivered(reading(playing: false))
        m.setHomeOpen(true)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(clock.requested.get().isEmpty, "paused: the progress does not move, so nothing ticks")
        m.adapterDelivered(reading(playing: true))
        #expect(await eventually { clock.requested.get().count >= 2 })
        #expect(Set(clock.requested.get()) == [.seconds(1)])
        m.setHomeOpen(false)
        m.setClosedIndicatorWanted(false)
        try? await Task.sleep(for: .milliseconds(60))
        let n = clock.requested.get().count
        try? await Task.sleep(for: .milliseconds(60))
        #expect(clock.requested.get().count == n, "closed, no indicator: no tick")
        m.setBackground(false)
    }

    @Test func theProgressMovesBetweenAdapterEventsWhileTheHomeIsOpen() async {
        let clock = CountingClock()
        let m = model([], running: [spotify], clock: clock)
        let start = Date().addingTimeInterval(-5)
        m.adapterDelivered(NowPlayingAdapterReading(title: "T", artist: "A", album: "Al", artworkData: nil, isPlaying: true,
                                                    position: 10, duration: 100, rate: 1, sampledAt: start,
                                                    bundleID: spotify))
        #expect((m.snapshot?.position ?? 0) >= 14.9, "extrapolated from the sampling time")
        m.setHomeOpen(false)
    }
}

/// A set of running apps a test can change.
final class RunningSet: RunningAppChecking, @unchecked Sendable {
    private let ids: Box<Set<String>>
    init(_ ids: Set<String> = []) { self.ids = Box(ids) }
    func set(_ new: Set<String>) { ids.set(new) }
    func isRunning(bundleID: String) -> Bool { ids.get().contains(bundleID) }
}

/// Stands for the NSWorkspace launch / terminate notifications.
@MainActor
final class FakeLifecycle: AppLifecycleWatching {
    private(set) var started = false
    private(set) var stopped = false
    private var handler: (@MainActor () -> Void)?
    func start(bundleIDs: [String], onChange: @escaping @MainActor () -> Void) {
        started = true; stopped = false; handler = onChange
    }
    func stop() { stopped = true; started = false; handler = nil }
    func fire() { handler?() }
}

/// The compiled script is cached: a status script runs every second while the Home is open.
@Suite struct ScriptCacheTests {
    @Test func theSameSourceIsCompiledOnce() {
        var made = 0
        var cache = CompiledScriptCache<Int>()
        for _ in 0..<3 { _ = cache.script(for: "status") { _ in made += 1; return made } }
        let other = cache.script(for: "artwork") { _ in made += 1; return made }
        #expect(made == 2 && other == 2)
        #expect(cache.script(for: "status") { _ in nil } == 1, "a hit never calls the factory again")
    }

    @Test func aSourceThatDoesNotCompileIsNotCached() {
        var cache = CompiledScriptCache<Int>()
        #expect(cache.script(for: "bad") { _ in nil } == nil)
        #expect(cache.script(for: "bad") { _ in 7 } == 7)
    }

    @Test func theCacheIsBounded() {
        var made = 0
        var cache = CompiledScriptCache<Int>(limit: 2)
        for source in ["a", "b", "c"] { _ = cache.script(for: source) { _ in made += 1; return made } }
        _ = cache.script(for: "a") { _ in made += 1; return made }   // evicted by the overflow: compiled again
        #expect(made == 4)
    }
}
