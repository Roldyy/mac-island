import Foundation
import Testing
@testable import DisplayFeature

@MainActor private final class FakeScanner: RunningAppScanning {
    var apps: [AppSnapshot] = []
    func snapshot() -> [AppSnapshot] { apps }
}

@MainActor private final class FakeTerminator: AppTerminating {
    var terminated: [Int32] = []
    func terminate(pid: Int32) -> Bool { terminated.append(pid); return true }
}

@Suite @MainActor struct AutoQuitModelTests {
    private func make(enabled: Bool = true, dryRun: Bool = false) -> (AutoQuitModel, FakeScanner, FakeTerminator, Clock, TempDefaults) {
        let temp = TempDefaults()
        var settings = DisplaySettings(defaults: temp.defaults)
        settings.autoQuitEnabled = enabled
        settings.autoQuitDryRun = dryRun
        let scanner = FakeScanner()
        let term = FakeTerminator()
        let clock = Clock()
        let model = AutoQuitModel(settings: settings, scanner: scanner, terminator: term,
                                  clock: { clock.now }, ownPID: 1, sleep: { _ in try? await Task.sleep(nanoseconds: 1_000_000_000) })
        return (model, scanner, term, clock, temp)
    }

    final class Clock: @unchecked Sendable { var now = t0 }

    @Test func initialStateComesFromTheMigratedKeys() {
        let (model, _, _, _, _) = make(enabled: true)
        #expect(model.enabled)
        #expect(model.delayMinutes == 30)
    }

    @Test func quitsAnIdleAppOnlyAfterDelayAndCountdown() {
        let (model, scanner, term, clock, _) = make()
        scanner.apps = [app(10)]
        model.tick()
        clock.now = at(30); model.tick()
        #expect(model.pending.map(\.pid) == [10])
        #expect(term.terminated.isEmpty)
        clock.now = at(31); model.tick()
        #expect(term.terminated == [10])
    }

    @Test func dryRunNeverTerminates() {
        let (model, scanner, term, clock, _) = make(dryRun: true)
        scanner.apps = [app(10)]
        model.tick()
        clock.now = at(30); model.tick()
        clock.now = at(120); model.tick()
        #expect(term.terminated.isEmpty)
        #expect(model.pending.count == 1)
    }

    @Test func disabledDoesNothing() {
        let (model, scanner, term, clock, _) = make(enabled: false)
        scanner.apps = [app(10)]
        model.tick()
        clock.now = at(120); model.tick()
        #expect(term.terminated.isEmpty && model.pending.isEmpty)
    }

    @Test func keepingAnAppAddsAnExclusionAndDropsItFromPending() {
        let (model, scanner, term, clock, _) = make(dryRun: true)
        scanner.apps = [app(10, "keep.me")]
        model.tick()
        clock.now = at(30); model.tick()
        #expect(model.pending.count == 1)
        model.addExclusion("keep.me")
        #expect(model.pending.isEmpty)
        #expect(model.exclusions == ["keep.me"])
        clock.now = at(31); model.tick()
        #expect(model.pending.isEmpty && term.terminated.isEmpty)
        model.removeExclusion("keep.me")
        #expect(model.exclusions.isEmpty)
    }

    @Test func delayIsClamped() {
        let (model, _, _, _, _) = make()
        model.delayMinutes = 0
        #expect(model.delayMinutes == 1)
        model.delayMinutes = 999_999
        #expect(model.delayMinutes == DisplaySettings.maxDelayMinutes)
    }

    @Test func startAndStopAreIdempotent() {
        let (model, _, _, _, _) = make()
        model.stop()
        model.start()
        model.start()
        #expect(model.isRunning)
        model.stop()
        model.stop()
        #expect(!model.isRunning)
    }
}
