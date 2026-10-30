import Testing
@testable import DisplayFeature

@Suite struct AutoQuitEngineTests {
    let config = AutoQuitConfig(delay: 30 * 60, userExclusions: [], ownPID: 1)

    private func engine() -> AutoQuitEngine { AutoQuitEngine(countdown: 60) }

    @Test func neverActsOnTheFirstScan() {
        var e = engine()
        let out = e.tick(apps: [app(10)], now: at(0), config: config, enabled: true, dryRun: false)
        #expect(out.pending.isEmpty)
        #expect(out.terminate.isEmpty)
    }

    @Test func waitsOneFullIntervalThenAnnouncesThenTerminates() {
        var e = engine()
        _ = e.tick(apps: [app(10)], now: at(0), config: config, enabled: true, dryRun: false)
        var out = e.tick(apps: [app(10)], now: at(29), config: config, enabled: true, dryRun: false)
        #expect(out.pending.isEmpty)
        out = e.tick(apps: [app(10)], now: at(30), config: config, enabled: true, dryRun: false)
        #expect(out.pending.map(\.pid) == [10])
        #expect(out.pending.first?.deadline == at(31))
        #expect(out.terminate.isEmpty)
        out = e.tick(apps: [app(10)], now: at(30.5), config: config, enabled: true, dryRun: false)
        #expect(out.terminate.isEmpty)
        out = e.tick(apps: [app(10)], now: at(31), config: config, enabled: true, dryRun: false)
        #expect(out.terminate == [10])
        #expect(out.pending.isEmpty)
    }

    @Test func appThatBecomesActiveDuringTheCountdownIsSpared() {
        var e = engine()
        _ = e.tick(apps: [app(10)], now: at(0), config: config, enabled: true, dryRun: false)
        _ = e.tick(apps: [app(10)], now: at(30), config: config, enabled: true, dryRun: false)
        let out = e.tick(apps: [app(10, windows: 1)], now: at(30.9), config: config, enabled: true, dryRun: false)
        #expect(out.pending.isEmpty)
        #expect(out.terminate.isEmpty)
        let later = e.tick(apps: [app(10)], now: at(31.5), config: config, enabled: true, dryRun: false)
        #expect(later.pending.isEmpty)  // clock restarted at 30.9
    }

    @Test func dryRunAnnouncesButNeverTerminates() {
        var e = engine()
        _ = e.tick(apps: [app(10)], now: at(0), config: config, enabled: true, dryRun: true)
        _ = e.tick(apps: [app(10)], now: at(30), config: config, enabled: true, dryRun: true)
        let out = e.tick(apps: [app(10)], now: at(90), config: config, enabled: true, dryRun: true)
        #expect(out.pending.map(\.pid) == [10])
        #expect(out.terminate.isEmpty)
    }

    @Test func disabledClearsEverythingAndRestartsTheWait() {
        var e = engine()
        _ = e.tick(apps: [app(10)], now: at(0), config: config, enabled: true, dryRun: false)
        _ = e.tick(apps: [app(10)], now: at(30), config: config, enabled: true, dryRun: false)
        var out = e.tick(apps: [app(10)], now: at(31), config: config, enabled: false, dryRun: false)
        #expect(out.pending.isEmpty && out.terminate.isEmpty)
        // Re-enabled: counts as a fresh launch, so nothing before another full interval.
        out = e.tick(apps: [app(10)], now: at(32), config: config, enabled: true, dryRun: false)
        #expect(out.pending.isEmpty)
        out = e.tick(apps: [app(10)], now: at(61), config: config, enabled: true, dryRun: false)
        #expect(out.pending.isEmpty)
        out = e.tick(apps: [app(10)], now: at(62), config: config, enabled: true, dryRun: false)
        #expect(out.pending.map(\.pid) == [10])
    }

    @Test func aTerminatedPidIsNotRetried() {
        var e = engine()
        _ = e.tick(apps: [app(10)], now: at(0), config: config, enabled: true, dryRun: false)
        _ = e.tick(apps: [app(10)], now: at(30), config: config, enabled: true, dryRun: false)
        _ = e.tick(apps: [app(10)], now: at(31), config: config, enabled: true, dryRun: false)
        let out = e.tick(apps: [app(10)], now: at(40), config: config, enabled: true, dryRun: false)
        #expect(out.pending.isEmpty && out.terminate.isEmpty)
    }
}
