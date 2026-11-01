import CoreGraphics
import Foundation
import IslandTestSupport
import Testing
@testable import PortKit

/// Lane W3D, the inactivity half. The logic of Mac Island's former Display module (its tests moved here with
/// it), now under `AutoQuitSafety`, plus the monitor driven by fakes: a fake workspace scan, a fake terminator
/// and a fake clock. Nothing here touches a real app.
@MainActor
@Suite struct AutoQuitIdleTests {
    // MARK: Fixtures

    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    private func app(_ pid: Int32, _ bundle: String? = nil, regular: Bool = true, front: Bool = false,
                     audio: Bool = false, windows: Int = 0, hidden: Bool = false) -> AutoQuitAppSnapshot {
        AutoQuitAppSnapshot(pid: pid, bundleID: bundle ?? "test.app\(pid)", name: "App\(pid)", isRegular: regular,
                            isFrontmost: front, isPlayingAudio: audio, windowCount: windows, isHidden: hidden)
    }

    private var config: AutoQuitIdleConfig {
        AutoQuitIdleConfig(delay: 30 * 60, neverQuit: ["test.app9"], ownPID: 1, ownBundleIDs: ["be.roldy.macisland"])
    }

    // MARK: Planner

    private func plan(_ apps: [AutoQuitAppSnapshot], last: [Int32: Double], now: Double = 60, since: Double = 0,
                      config: AutoQuitIdleConfig? = nil) -> [Int32] {
        AutoQuitIdlePlanner.candidates(apps: apps, lastActive: last.mapValues { at($0) }, now: at(now),
                                       monitoringSince: at(since), config: config ?? self.config).map(\.pid)
    }

    @Test func anIdleRegularAppPastTheDelayIsACandidate() {
        #expect(plan([app(10)], last: [10: 0]) == [10])
    }

    @Test func notIdleLongEnoughIsKept() {
        #expect(plan([app(10)], last: [10: 40]).isEmpty)
        #expect(plan([app(10)], last: [10: 30], now: 59.99).isEmpty)
        #expect(plan([app(10)], last: [10: 30], now: 60) == [10])
    }

    @Test func anAppWithAWindowInAnyStateIsKept() {
        #expect(plan([app(10, windows: 1)], last: [10: 0]).isEmpty)
        #expect(plan([app(10, hidden: true)], last: [10: 0]).isEmpty, "hidden with Cmd+H: in use")
    }

    @Test func protectedAppsAreNeverCandidatesWhateverTheirIdleTime() {
        #expect(plan([app(10, front: true)], last: [10: 0]).isEmpty, "the app in front")
        #expect(plan([app(10, audio: true)], last: [10: 0]).isEmpty, "playing sound")
        #expect(plan([app(10, regular: false)], last: [10: 0]).isEmpty, "menu bar and agent apps")
        #expect(plan([app(1)], last: [1: 0]).isEmpty, "Mac Island's own process")
        #expect(plan([app(10, "be.roldy.macisland")], last: [10: 0]).isEmpty, "Mac Island's own bundle id")
        #expect(plan([app(9)], last: [9: 0]).isEmpty, "the never-quit list")
        for id in ["com.apple.finder", "com.apple.dock", "com.apple.loginwindow", "com.apple.systemuiserver"] {
            #expect(plan([app(10, id)], last: [10: 0]).isEmpty, "\(id)")
        }
        let anonymous = AutoQuitAppSnapshot(pid: 10, bundleID: nil, name: "x", isRegular: true, isFrontmost: false,
                                            isPlayingAudio: false, windowCount: 0)
        #expect(plan([anonymous], last: [10: 0]).isEmpty, "no bundle id: nothing to decide on")
    }

    @Test func unknownLastActiveIsKeptAndNothingHappensBeforeOneFullInterval() {
        #expect(plan([app(10)], last: [:]).isEmpty)
        #expect(plan([app(10)], last: [10: 0], now: 45, since: 20).isEmpty)
        #expect(plan([app(10)], last: [10: 0], now: 50, since: 20) == [10])
    }

    @Test func theResultIsSortedByPidAndBuiltInsAreExactIds() {
        #expect(plan([app(30), app(20), app(10)], last: [10: 0, 20: 0, 30: 0]) == [10, 20, 30])
        #expect(plan([app(10, "com.apple.finder.helper")], last: [10: 0]) == [10])
    }

    // MARK: Tracker

    @Test func theTrackerStartsTheClockAtFirstSightAndKeepsTheTimestampWhileIdle() {
        var tracker = AutoQuitIdleTracker()
        tracker.update([app(10)], now: at(5))
        tracker.update([app(10)], now: at(25))
        #expect(tracker.lastActive[10] == at(5))
        tracker.update([app(10, windows: 2), app(11, front: true), app(12, audio: true)], now: at(30))
        #expect(tracker.lastActive[10] == at(30) && tracker.lastActive[11] == at(30) && tracker.lastActive[12] == at(30))
        tracker.update([app(11)], now: at(31))
        #expect(tracker.lastActive[10] == nil, "gone apps are forgotten")
    }

    // MARK: Engine

    private func engine() -> AutoQuitIdleEngine { AutoQuitIdleEngine(countdown: 60) }

    @Test func theEngineNeverActsOnTheFirstScanThenAnnouncesThenTerminates() {
        var e = engine()
        var out = e.tick(apps: [app(10)], now: at(0), config: config, enabled: true, dryRun: false)
        #expect(out.pending.isEmpty && out.terminate.isEmpty)
        out = e.tick(apps: [app(10)], now: at(29), config: config, enabled: true, dryRun: false)
        #expect(out.pending.isEmpty)
        out = e.tick(apps: [app(10)], now: at(30), config: config, enabled: true, dryRun: false)
        #expect(out.pending.map(\.pid) == [10] && out.pending.first?.deadline == at(31) && out.terminate.isEmpty)
        out = e.tick(apps: [app(10)], now: at(30.5), config: config, enabled: true, dryRun: false)
        #expect(out.terminate.isEmpty)
        out = e.tick(apps: [app(10)], now: at(31), config: config, enabled: true, dryRun: false)
        #expect(out.terminate == [10] && out.pending.isEmpty)
        out = e.tick(apps: [app(10)], now: at(40), config: config, enabled: true, dryRun: false)
        #expect(out.pending.isEmpty && out.terminate.isEmpty, "a pid already asked is not asked again")
    }

    @Test func anAppThatBecomesActiveDuringTheCountdownIsSpared() {
        var e = engine()
        _ = e.tick(apps: [app(10)], now: at(0), config: config, enabled: true, dryRun: false)
        _ = e.tick(apps: [app(10)], now: at(30), config: config, enabled: true, dryRun: false)
        let out = e.tick(apps: [app(10, windows: 1)], now: at(30.9), config: config, enabled: true, dryRun: false)
        #expect(out.pending.isEmpty && out.terminate.isEmpty)
        #expect(e.tick(apps: [app(10)], now: at(31.5), config: config, enabled: true, dryRun: false).pending.isEmpty,
                "the clock restarted when the window showed")
    }

    @Test func dryRunAnnouncesButNeverTerminates() {
        var e = engine()
        _ = e.tick(apps: [app(10)], now: at(0), config: config, enabled: true, dryRun: true)
        _ = e.tick(apps: [app(10)], now: at(30), config: config, enabled: true, dryRun: true)
        let out = e.tick(apps: [app(10)], now: at(90), config: config, enabled: true, dryRun: true)
        #expect(out.pending.map(\.pid) == [10] && out.terminate.isEmpty)
    }

    @Test func disabledClearsEverythingAndRestartsTheWait() {
        var e = engine()
        _ = e.tick(apps: [app(10)], now: at(0), config: config, enabled: true, dryRun: false)
        _ = e.tick(apps: [app(10)], now: at(30), config: config, enabled: true, dryRun: false)
        var out = e.tick(apps: [app(10)], now: at(31), config: config, enabled: false, dryRun: false)
        #expect(out.pending.isEmpty && out.terminate.isEmpty)
        out = e.tick(apps: [app(10)], now: at(32), config: config, enabled: true, dryRun: false)
        #expect(out.pending.isEmpty)
        out = e.tick(apps: [app(10)], now: at(61), config: config, enabled: true, dryRun: false)
        #expect(out.pending.isEmpty)
        out = e.tick(apps: [app(10)], now: at(62), config: config, enabled: true, dryRun: false)
        #expect(out.pending.map(\.pid) == [10])
    }

    // MARK: Window counter and audio attribution

    private func win(pid: Int, layer: Int = 0, alpha: Double = 1, w: Double = 400, h: Double = 300) -> [String: Any] {
        ["kCGWindowOwnerPID": pid, "kCGWindowLayer": layer, "kCGWindowAlpha": alpha,
         "kCGWindowBounds": ["X": 0, "Y": 0, "Width": w, "Height": h]]
    }

    @Test func theWindowCounterCountsLayerZeroWindowsPerOwnerInAnyState() {
        let counts = AutoQuitWindowCounter.counts(from: [win(pid: 10), win(pid: 10), win(pid: 11)])
        #expect(counts[10] == 2 && counts[11] == 1)
        let ignored = AutoQuitWindowCounter.counts(from: [
            win(pid: 10, layer: 25), win(pid: 10, alpha: 0), win(pid: 10, w: 1, h: 1), ["kCGWindowLayer": 0], [:],
        ])
        #expect(ignored.isEmpty)
        var minimized = win(pid: 10)
        minimized["kCGWindowIsOnscreen"] = false
        #expect(AutoQuitWindowCounter.counts(from: [minimized])[10] == 1, "off screen still counts as a window")
        var asked: CGWindowListOption?
        _ = AutoQuitWindowCounter.currentCounts { options, _ in asked = options; return [] }
        #expect(asked?.contains(.optionOnScreenOnly) == false && asked?.contains(.excludeDesktopElements) == true)
    }

    private let apps: [Int32: String] = [100: "com.vendor.browser", 200: "com.vendor.player"]
    private let known: Set<Int32> = [100, 200, 300]

    private func attribute(_ playing: [AutoQuitPlayingProcess], parents: [Int32: Int32] = [:]) -> AutoQuitAudio.Attribution {
        AutoQuitAudio.attribute(playing: playing, apps: apps, knownPIDs: known) { parents[$0] }
    }

    @Test func soundIsAttributedToTheAppThatOwnsTheProcess() {
        #expect(attribute([AutoQuitPlayingProcess(pid: 200, bundleID: "com.vendor.player")])
                == .init(appPIDs: [200], hasUnattributed: false))
        #expect(attribute([AutoQuitPlayingProcess(pid: 500, bundleID: nil)], parents: [500: 450, 450: 100])
                == .init(appPIDs: [100], hasUnattributed: false), "a helper child goes to its parent app")
        #expect(attribute([AutoQuitPlayingProcess(pid: 500, bundleID: "com.vendor.browser.helper.audio")],
                          parents: [500: 1]) == .init(appPIDs: [100], hasUnattributed: false), "by bundle prefix")
    }

    @Test func soundNobodyOwnsIsFlaggedSoNobodyIsQuitBlindly() {
        let prefix = attribute([AutoQuitPlayingProcess(pid: 500, bundleID: "com.vendor.browserx")], parents: [500: 1])
        #expect(prefix.appPIDs.isEmpty && prefix.hasUnattributed, "the prefix must end at a dot")
        #expect(attribute([AutoQuitPlayingProcess(pid: 500, bundleID: "com.apple.unrelated")], parents: [500: 1])
                == .init(appPIDs: [], hasUnattributed: true))
        #expect(attribute([AutoQuitPlayingProcess(pid: 300, bundleID: "com.vendor.agent")])
                == .init(appPIDs: [], hasUnattributed: false), "a known agent app is not a mystery")
        #expect(attribute([AutoQuitPlayingProcess(pid: 500, bundleID: nil)], parents: [500: 501, 501: 500]).hasUnattributed,
                "a parent cycle ends")
    }

    // MARK: Monitor, with fakes

    @MainActor final class FakeScanner: AutoQuitIdleScanning {
        var apps: [AutoQuitAppSnapshot] = []
        var scans = 0
        func snapshot() -> [AutoQuitAppSnapshot] { scans += 1; return apps }
    }

    @MainActor final class FakeTerminator: AutoQuitTerminating {
        var terminated: [Int32] = []
        func terminate(pid: Int32) -> Bool { terminated.append(pid); return true }
    }

    final class Clock: @unchecked Sendable { var now = Date(timeIntervalSinceReferenceDate: 1_000_000) }

    private struct Rig {
        let monitor: AutoQuitIdleMonitor
        let scanner: FakeScanner
        let terminator: FakeTerminator
        let clock: Clock
        let bench: (defaults: UserDefaults, cleanup: () -> Void)
        let world: AutoQuitSafetyTests.World
    }

    private func rig(enabled: Bool = true, dryRun: Bool = false, available: Bool = true,
                     accessibility: Bool = true) -> Rig {
        let bench = TestDefaults.make()
        bench.defaults.set(enabled, forKey: AutoQuitIdleKeys.enabled)
        bench.defaults.set(dryRun, forKey: AutoQuitIdleKeys.dryRun)
        let scanner = FakeScanner()
        let terminator = FakeTerminator()
        let clock = Clock()
        let world = AutoQuitSafetyTests.World()
        let monitor = AutoQuitIdleMonitor(
            defaults: { bench.defaults }, isAvailable: { available }, hasAccessibility: { accessibility }, scanner: scanner, terminator: terminator,
            gate: world.gate, clock: { clock.now },
            sleep: { _ in try? await Task.sleep(nanoseconds: 1_000_000_000) })
        return Rig(monitor: monitor, scanner: scanner, terminator: terminator, clock: clock, bench: bench, world: world)
    }

    private func advance(_ r: Rig, minutes: Double) { r.clock.now = Date(timeIntervalSinceReferenceDate: 1_000_000 + minutes * 60) }

    @Test func offByDefaultNothingScansAndNothingIsAnnounced() {
        let r = rig(enabled: false)
        defer { r.bench.cleanup() }
        r.scanner.apps = [app(10)]
        r.monitor.sync()
        r.monitor.tick()
        advance(r, minutes: 120); r.monitor.tick()
        #expect(!r.monitor.isRunning && r.scanner.scans == 0)
        #expect(r.monitor.pending.isEmpty && r.terminator.terminated.isEmpty)
        let unset = TestDefaults.make()
        defer { unset.cleanup() }
        #expect(AutoQuitIdleKeys.isDryRun(in: unset.defaults), "an unset dry-run key means simulation")
    }

    @Test func aRegistryThatHoldsTheFeatureOffStopsTheLoopEvenWithTheToggleOn() {
        let r = rig(available: false)
        defer { r.bench.cleanup() }
        r.monitor.sync()
        #expect(!r.monitor.isRunning)
        r.scanner.apps = [app(10)]
        r.monitor.tick()
        advance(r, minutes: 120); r.monitor.tick()
        #expect(r.terminator.terminated.isEmpty)
    }

    @Test func withoutAccessibilityNothingRuns() {
        let r = rig(accessibility: false)
        defer { r.bench.cleanup() }
        r.scanner.apps = [app(10)]
        r.monitor.sync()
        r.monitor.tick()
        advance(r, minutes: 120); r.monitor.tick()
        #expect(!r.monitor.isRunning && r.scanner.scans == 0 && r.terminator.terminated.isEmpty)
    }

    @Test func anIdleAppIsAskedToQuitOnlyAfterTheDelayAndTheCountdown() {
        let r = rig()
        defer { r.bench.cleanup() }
        r.scanner.apps = [app(10)]
        r.monitor.tick()
        advance(r, minutes: 30); r.monitor.tick()
        #expect(r.monitor.pending.map(\.pid) == [10] && r.terminator.terminated.isEmpty)
        advance(r, minutes: 31); r.monitor.tick()
        #expect(r.terminator.terminated == [10])
    }

    @Test func simulationNeverTerminates() {
        let r = rig(dryRun: true)
        defer { r.bench.cleanup() }
        r.scanner.apps = [app(10)]
        r.monitor.tick()
        advance(r, minutes: 30); r.monitor.tick()
        advance(r, minutes: 120); r.monitor.tick()
        #expect(r.terminator.terminated.isEmpty && r.monitor.pending.count == 1)
    }

    @Test func theLiveGateHasTheLastWordRightBeforeTheQuit() {
        let r = rig()
        defer { r.bench.cleanup() }
        r.scanner.apps = [app(10), app(11)]
        r.monitor.tick()
        advance(r, minutes: 30); r.monitor.tick()
        #expect(r.monitor.pending.map(\.pid) == [10, 11])
        // Between the scan and the quit: 10 came to the front, 11 started playing sound.
        r.world.frontmost = 10
        r.world.playing = [11]
        advance(r, minutes: 31); r.monitor.tick()
        #expect(r.terminator.terminated.isEmpty, "both were vetoed by the live look")
    }

    @Test func aDueAppThatTheWorldNowProtectsIsNeverQuit() {
        let r = rig()
        defer { r.bench.cleanup() }
        r.scanner.apps = [app(10, "com.apple.finder"), app(11, "be.roldy.macisland"), app(1)]
        r.monitor.tick()
        advance(r, minutes: 120); r.monitor.tick()
        advance(r, minutes: 125); r.monitor.tick()
        #expect(r.terminator.terminated.isEmpty && r.monitor.pending.isEmpty)
    }

    @Test func theSharedNeverQuitListIsReadEveryScan() {
        let r = rig(dryRun: true)
        defer { r.bench.cleanup() }
        r.scanner.apps = [app(10, "keep.me")]
        r.monitor.tick()
        advance(r, minutes: 30); r.monitor.tick()
        #expect(r.monitor.pending.count == 1)
        r.bench.defaults.set(["keep.me"], forKey: DefaultsKey.autoQuitExceptions)
        r.monitor.tick()
        #expect(r.monitor.pending.isEmpty)
    }

    @Test func startAndStopAreIdempotentAndStopForgetsTheClocks() {
        let r = rig(dryRun: true)
        defer { r.bench.cleanup() }
        r.monitor.stop()
        r.monitor.sync()
        r.monitor.sync()
        #expect(r.monitor.isRunning)
        r.monitor.stop()
        r.monitor.stop()
        #expect(!r.monitor.isRunning && r.monitor.pending.isEmpty)
    }

    @Test func theDelayIsClampedAndReadsTheOldModulesKey() {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        #expect(AutoQuitIdleKeys.delay(in: bench.defaults) == 30)
        bench.defaults.set(0, forKey: "autoQuitDelayMinutes")
        #expect(AutoQuitIdleKeys.delay(in: bench.defaults) == 1)
        bench.defaults.set(999_999, forKey: "autoQuitDelayMinutes")
        #expect(AutoQuitIdleKeys.delay(in: bench.defaults) == AutoQuitIdleKeys.maxDelayMinutes)
        bench.defaults.set(45, forKey: "autoQuitDelayMinutes")
        #expect(AutoQuitIdleKeys.delay(in: bench.defaults) == 45)
    }

    @Test func theOldModulesExclusionsJoinTheSharedListOnceAndNothingIsRemoved() {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        bench.defaults.set(["old.one", "old.two"], forKey: AutoQuitIdleKeys.legacyExclusions)
        bench.defaults.set(["mine.kept"], forKey: DefaultsKey.autoQuitExceptions)
        AutoQuitIdleKeys.adoptLegacyExclusions(in: bench.defaults)
        let merged = bench.defaults.stringArray(forKey: DefaultsKey.autoQuitExceptions) ?? []
        #expect(Set(merged) == Set(["mine.kept", "old.one", "old.two"] + Defaults.mandatoryAutoQuitExceptionBundleIDs))
        // Once: a later removal by the person is not undone.
        bench.defaults.set(["mine.kept"], forKey: DefaultsKey.autoQuitExceptions)
        AutoQuitIdleKeys.adoptLegacyExclusions(in: bench.defaults)
        #expect(bench.defaults.stringArray(forKey: DefaultsKey.autoQuitExceptions) == ["mine.kept"])
    }

    // MARK: The old `autoQuitEnabled` (our Display module's IDLE switch, upstream's LAST-WINDOW switch now)

    @Test func anOldModuleFlagMovesToTheIdleSwitchAndTheLastWindowKeyGoesOff() {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        bench.defaults.set(true, forKey: DefaultsKey.autoQuitEnabled)
        bench.defaults.set(45, forKey: AutoQuitIdleKeys.delayMinutes)  // one of the old module's own keys
        AutoQuitIdleKeys.adoptLegacyExclusions(in: bench.defaults)  // the lane's bind-time call
        #expect(bench.defaults.bool(forKey: AutoQuitIdleKeys.enabled), "the idle quit the person had on stays on")
        #expect(bench.defaults.object(forKey: DefaultsKey.autoQuitEnabled) as? Bool == false,
                "upstream's quit-when-the-last-window-closes never starts by itself")
        #expect(bench.defaults.bool(forKey: AutoQuitIdleKeys.lastWindowResetKey), "the page says so")
    }

    @Test func aFlagNobodyCanAttributeTurnsLastWindowOffAndEnablesNothing() {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        bench.defaults.set(true, forKey: DefaultsKey.autoQuitEnabled)
        AutoQuitIdleKeys.settleLegacyEnabledFlag(in: bench.defaults)
        #expect(bench.defaults.object(forKey: DefaultsKey.autoQuitEnabled) as? Bool == false)
        #expect(bench.defaults.object(forKey: AutoQuitIdleKeys.enabled) == nil)
        #expect(bench.defaults.bool(forKey: AutoQuitIdleKeys.lastWindowResetKey))
    }

    @Test func anIdleChoiceAlreadyMadeIsNotOverridden() {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        bench.defaults.set(true, forKey: DefaultsKey.autoQuitEnabled)
        bench.defaults.set(true, forKey: AutoQuitIdleKeys.dryRun)
        bench.defaults.set(false, forKey: AutoQuitIdleKeys.enabled)
        AutoQuitIdleKeys.settleLegacyEnabledFlag(in: bench.defaults)
        #expect(bench.defaults.object(forKey: AutoQuitIdleKeys.enabled) as? Bool == false)
    }

    @Test func offOrAbsentIsLeftAloneAndASwitchOnInThePageSticks() {
        let absent = TestDefaults.make()
        defer { absent.cleanup() }
        AutoQuitIdleKeys.settleLegacyEnabledFlag(in: absent.defaults)
        #expect(absent.defaults.object(forKey: DefaultsKey.autoQuitEnabled) == nil)
        #expect(!absent.defaults.bool(forKey: AutoQuitIdleKeys.lastWindowResetKey), "nothing was reset: no note")

        let stored = TestDefaults.make()
        defer { stored.cleanup() }
        stored.defaults.set(true, forKey: DefaultsKey.autoQuitEnabled)
        AutoQuitIdleKeys.settleLegacyEnabledFlag(in: stored.defaults)
        stored.defaults.set(true, forKey: DefaultsKey.autoQuitEnabled)  // the person switches it on in the page
        AutoQuitIdleKeys.settleLegacyEnabledFlag(in: stored.defaults)
        #expect(stored.defaults.bool(forKey: DefaultsKey.autoQuitEnabled), "once: a later choice is never undone")
    }
}
