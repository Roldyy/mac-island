import Testing
@testable import FanShared

/// The helper's brain against a fake SMC and a fake clock. No real SMC, no real time.
@Suite struct FanControlCoreTests {
    let smc = FakeSMC()
    let clock = FakeClock()
    let thermal = ThermalBox()

    private func makeCore(timeout: Double = 8) -> FanControlCore {
        FanControlCore(reader: smc, writer: smc, clock: clock, watchdogTimeout: timeout) { [thermal] in thermal.snapshot }
    }

    @Test func manualWriteSequenceIsUnlockThenModeThenTarget() {
        let core = makeCore()
        let r = core.perform(.setTarget(fan: 0, rpm: 3000), client: 1)
        #expect(r.status == .applied)
        #expect(r.appliedRPM == 3000)
        #expect(smc.writes.map(\.key) == ["Ftst", "F0Md", "F0Tg"])
        #expect(smc.writes.map(\.value) == [1, 1, 3000])
        #expect(core.isManualActive)
        #expect(core.watchdog.isArmed)
    }

    @Test func withoutAnUnlockKeyTheSequenceSkipsIt() {
        let smc = FakeSMC(withUnlock: false)
        let core = FanControlCore(reader: smc, writer: smc, clock: clock) { ThermalSnapshot(maxCelsius: 60, pressure: .nominal) }
        #expect(core.perform(.setTarget(fan: 1, rpm: 4000), client: 1).status == .applied)
        #expect(smc.writes.map(\.key) == ["F1Md", "F1Tg"])
    }

    @Test func helperReClampsWhateverTheAppSends() {
        let core = makeCore()
        #expect(core.perform(.setTarget(fan: 0, rpm: 10), client: 1).appliedRPM == 2317)
        clock.advance(2)
        #expect(core.perform(.setTarget(fan: 0, rpm: 1e9), client: 1).appliedRPM == 7826)
        #expect(smc.number("F0Tg") == 7826)
    }

    @Test func limitsComeFromTheSMCNotFromTheRequest() {
        smc.setFloat("F0Mn", 3000)
        let core = makeCore()
        #expect(core.perform(.setTarget(fan: 0, rpm: 2500), client: 1).appliedRPM == 3000)
    }

    @Test func rejectedRequestsWriteNothing() {
        let core = makeCore()
        #expect(core.perform(.setTarget(fan: 5, rpm: 3000), client: 1).status == .rejected)
        #expect(core.perform(.setTarget(fan: 0, rpm: .nan), client: 1).status == .rejected)
        smc.setFloat("F1Mn", 0)
        #expect(core.perform(.setTarget(fan: 1, rpm: 3000), client: 1).status == .rejected)
        #expect(smc.writes.isEmpty)
        #expect(!core.isManualActive)
    }

    @Test func rateLimitRefusesASecondChangeTooSoon() {
        let core = makeCore()
        #expect(core.perform(.setTarget(fan: 0, rpm: 3000), client: 1).status == .applied)
        clock.advance(0.4)
        let r = core.perform(.setTarget(fan: 0, rpm: 5000), client: 1)
        #expect(r.status == .rejected)
        #expect(r.reason == "rateLimited")
        #expect(smc.number("F0Tg") == 3000)
    }

    @Test func hotMachineForcesAutomaticInsteadOfManual() {
        let core = makeCore()
        thermal.snapshot = ThermalSnapshot(maxCelsius: 99, pressure: .nominal)
        let r = core.perform(.setTarget(fan: 0, rpm: 3000), client: 1)
        #expect(r.status == .forcedAutomatic)
        #expect(smc.number("F0Md") == 0)
        #expect(!smc.writes.contains { $0.key == "F0Tg" })
    }

    @Test func thermalOverrideWhileManualRestoresOnTick() {
        let core = makeCore()
        _ = core.perform(.setTarget(fan: 0, rpm: 3000), client: 1)
        thermal.snapshot = ThermalSnapshot(maxCelsius: nil, pressure: .nominal)   // sensor lost: fail closed
        #expect(core.tick() == .thermal)
        #expect(smc.number("F0Md") == 0)
        #expect(smc.number("Ftst") == 0)
        #expect(!core.isManualActive)
    }

    // MARK: - Crash of the app (requirement 5)

    @Test func appCrashWithoutInvalidationIsCaughtByTheWatchdog() {
        let core = makeCore(timeout: 8)
        _ = core.perform(.setTarget(fan: 0, rpm: 6000), client: 1)
        _ = core.perform(.setTarget(fan: 1, rpm: 6000), client: 1)
        clock.advance(2); #expect(core.heartbeat(client: 1))
        clock.advance(2); #expect(core.heartbeat(client: 1))
        // App hangs or dies: heartbeats stop. Nothing happens before the deadline...
        clock.advance(7.9); #expect(core.tick() == nil)
        #expect(smc.number("F0Md") == 1)
        // ...and automatic is restored as soon as it passes.
        clock.advance(0.2); #expect(core.tick() == .watchdog)
        #expect(smc.number("F0Md") == 0)
        #expect(smc.number("F1Md") == 0)
        #expect(smc.number("Ftst") == 0)
        #expect(!core.isManualActive)
        #expect(core.lastRestoreReason == .watchdog)
        #expect(!core.heartbeat(client: 1))   // a late heartbeat does not bring manual back
    }

    @Test func appCrashSeenAsConnectionInvalidationRestoresAtOnce() {
        let core = makeCore()
        _ = core.perform(.setTarget(fan: 0, rpm: 6000), client: 7)
        core.clientDisconnected(7)
        #expect(smc.number("F0Md") == 0)
        #expect(smc.number("Ftst") == 0)
        #expect(core.lastRestoreReason == .disconnected)
    }

    @Test func anotherClientDisconnectingDoesNotTouchTheOwnersFans() {
        let core = makeCore()
        _ = core.perform(.setTarget(fan: 0, rpm: 6000), client: 7)
        core.clientDisconnected(8)
        #expect(smc.number("F0Md") == 1)
        #expect(!core.heartbeat(client: 8))   // and cannot keep them manual either
        #expect(core.heartbeat(client: 7))
    }

    @Test func shutdownRestoresAndIsIdempotent() {
        let core = makeCore()
        _ = core.perform(.setTarget(fan: 0, rpm: 6000), client: 1)
        #expect(core.restoreAutomatic(.shutdown))
        let count = smc.writes.count
        #expect(core.restoreAutomatic(.shutdown))
        #expect(smc.writes.count == count)   // nothing manual left: no extra SMC writes
    }

    @Test func startupRecoveryOnlyWritesWhenAFanIsLeftManual() {
        let clean = makeCore()
        #expect(clean.recoverAtStartup())
        #expect(smc.writes.isEmpty)

        smc.setRaw("F1Md", .ui8, [1])
        smc.setRaw("Ftst", .ui8, [1])
        let afterCrash = makeCore()
        #expect(afterCrash.recoverAtStartup())
        #expect(smc.writes.map(\.key) == ["F1Md", "Ftst"])
        #expect(smc.number("F1Md") == 0)
    }

    @Test func startupRecoveryLeavesUnknownModeValuesAlone() {
        smc.setRaw("F0Md", .ui8, [3])
        #expect(makeCore().recoverAtStartup())
        #expect(smc.writes.isEmpty)
    }

    @Test func aFailedWriteRestoresAutomatic() {
        smc.failingWrites = ["F0Tg"]
        let core = makeCore()
        let r = core.perform(.setTarget(fan: 0, rpm: 3000), client: 1)
        #expect(r.status == .failed)
        #expect(smc.number("F0Md") == 0)
        #expect(smc.number("Ftst") == 0)
        #expect(!core.isManualActive)
    }

    @Test func anUnconfirmedModeWriteRestoresAutomatic() {
        smc.ignoredWrites = ["F0Md"]   // the SMC accepts but ignores it (what a refused M4 write may look like)
        let core = makeCore()
        let r = core.perform(.setTarget(fan: 0, rpm: 3000), client: 1)
        #expect(r.status == .failed)
        #expect(r.reason == "notConfirmed")
        #expect(smc.number("Ftst") == 0)
        #expect(!core.isManualActive)
    }

    @Test func aFailedRestoreIsRetriedOnEveryTickAndBlocksNewManual() {
        let core = makeCore()
        _ = core.perform(.setTarget(fan: 0, rpm: 3000), client: 1)
        smc.failingWrites = ["F0Md"]
        #expect(!core.restoreAutomatic(.clientRequest))
        #expect(core.restorePending)
        clock.advance(2)
        #expect(core.perform(.setTarget(fan: 1, rpm: 3000), client: 1).status == .failed)
        #expect(smc.number("F1Md") == 0)
        smc.failingWrites = []
        #expect(core.tick() == .clientRequest)
        #expect(!core.restorePending)
        #expect(smc.number("F0Md") == 0)
    }

    @Test func automaticForOneFanKeepsTheOtherManual() {
        let core = makeCore()
        _ = core.perform(.setTarget(fan: 0, rpm: 3000), client: 1)
        _ = core.perform(.setTarget(fan: 1, rpm: 3000), client: 1)
        #expect(core.perform(.automatic(fan: 0), client: 1).status == .automatic)
        #expect(smc.number("F0Md") == 0)
        #expect(smc.number("F1Md") == 1)
        #expect(smc.number("Ftst") == 1)
        #expect(core.perform(.automatic(fan: 1), client: 1).status == .automatic)
        #expect(smc.number("Ftst") == 0)
        #expect(!core.watchdog.isArmed)
        #expect(core.perform(.automatic(fan: 4), client: 1).status == .rejected)
    }

    @Test func allAutomaticRestoresEverything() {
        let core = makeCore()
        _ = core.perform(.setTarget(fan: 0, rpm: 3000), client: 1)
        _ = core.perform(.setTarget(fan: 1, rpm: 3000), client: 1)
        #expect(core.perform(.allAutomatic, client: 1).status == .automatic)
        #expect(smc.number("F0Md") == 0)
        #expect(smc.number("F1Md") == 0)
        #expect(smc.number("Ftst") == 0)
    }

    @Test func stateReportsReadingsAndManualFlag() {
        let core = makeCore()
        _ = core.perform(.setTarget(fan: 0, rpm: 3000), client: 1)
        let s = core.state()
        #expect(s.protocolVersion == FanHelperContract.protocolVersion)
        #expect(s.fans.count == 2)
        #expect(s.fans[0].mode == .manual)
        #expect(s.fans[1].mode == .automatic)
        #expect(s.manualActive)
        #expect(s.maxTemperatureCelsius == 60)
    }

    @Test func selfTestOnlyReads() {
        let core = makeCore()
        let report = core.selfTestReadOnly()
        #expect(smc.writes.isEmpty)
        #expect(report.fanCount == 2)
        #expect(report.fans.first?.minRPM == 2317)
        #expect(report.keys.contains { $0.name == "Ftst" && $0.type == "ui8 " && $0.size == 1 })
        #expect(report.keys.contains { $0.name == "F0Md" && $0.type == "ui8 " })
        #expect(report.keys.contains { $0.name == "F0Tg" && $0.type == "flt " && $0.size == 4 })
    }

    @Test func selfTestWorksOnAPureReader() {
        let reader = ReadOnlyFake()
        let report = FanSelfTest.run(reader: reader, thermal: ThermalSnapshot(maxCelsius: 50, pressure: .nominal))
        #expect(report.fanCount == 2)
        #expect(reader.inner.writes.isEmpty)
    }
}
