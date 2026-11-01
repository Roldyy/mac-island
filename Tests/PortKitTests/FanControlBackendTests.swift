import FansFeature
import Foundation
import IslandTestSupport
import Testing
@testable import PortKit

/// Records every command; never talks to a helper, an SMC or a real preference domain.
@MainActor
final class FakeFanDriver: FanDriving {
    var access: FanDriverAccess = .enabled
    var isReachable = true
    var isManualActive = false
    var onManualEnded: (@MainActor (String?) -> Void)?
    var fans: [FanDriverFan]? = FakeFanDriver.twoFans
    var log: [String] = []
    var targetOutcome: (Int, Double) -> FanDriverOutcome = { .applied(fan: $0, rpm: $1) }
    var returnOutcome: FanDriverOutcome = .automatic
    var onSetTarget: (() -> Void)?

    static let twoFans = [
        FanDriverFan(index: 0, actualRPM: 2300, minRPM: 2317, maxRPM: 7826, targetRPM: 2317, isManual: false),
        FanDriverFan(index: 1, actualRPM: 2400, minRPM: 2000, maxRPM: 6000, targetRPM: 2000, isManual: false),
    ]

    func count(_ prefix: String) -> Int { log.filter { $0.hasPrefix(prefix) }.count }

    func refreshAccess() {}
    func connectIfApproved() async { log.append("connect") }
    func installHelper() { log.append("install"); access = .requiresApproval }
    func openApprovalSettings() { log.append("openSettings") }
    func readFans() async -> [FanDriverFan]? { fans }

    func setTarget(fan: Int, rpm: Double) async -> FanDriverOutcome {
        log.append("set:\(fan):\(Int(rpm))")
        onSetTarget?()
        let outcome = targetOutcome(fan, rpm)
        if case .applied = outcome { isManualActive = true }
        return outcome
    }

    func returnAllToAutomatic() async -> FanDriverOutcome {
        log.append("auto")
        isManualActive = false
        return returnOutcome
    }

    func returnAllToAutomaticNow() {
        log.append("autoNow")
        isManualActive = false
    }
}

@MainActor
struct FanBench {
    let backend: FanControlBackend
    let driver: FakeFanDriver
    let defaults: UserDefaults
    let temperatures: Box<[FanControlTemperatureReading]>
    let thermal: Box<ProcessInfo.ThermalState>
    let driverRequests: Box<Int>
    let cleanup: () -> Void

    static func make(started: Bool = true, soc: Double? = 60) -> FanBench {
        let driver = FakeFanDriver()
        let bench = TestDefaults.make()
        let temps = Box<[FanControlTemperatureReading]>(
            soc.map { [FanControlTemperatureReading(source: .hottestSoC, celsius: $0)] } ?? [])
        let thermal = Box(ProcessInfo.ThermalState.nominal)
        let requests = Box(0)
        let defaults = bench.defaults
        let backend = FanControlBackend(environment: FanControlBackend.Environment(
            driver: { requests.value += 1; return driver },
            temperatures: { temps.value },
            thermalState: { thermal.value },
            defaults: { defaults },
            tickInterval: 0.01,
            schedulesTicks: false))
        if started { backend.start() }
        return FanBench(backend: backend, driver: driver, defaults: defaults, temperatures: temps, thermal: thermal,
                        driverRequests: requests, cleanup: bench.cleanup)
    }

    var journal: Bool { defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded) }
    var curve: FanControlConfiguration { .curve([FanControlConfiguration.defaultCurve]) }
}

/// Lane W6C: the policy over a fake driver. Nothing here reaches a fan, the helper, XPC or the SMC.
@MainActor
@Suite(.serialized) struct FanControlBackendTests {
    // MARK: Journal first, speeds, hand-back

    @Test func theJournalIsSetBeforeTheFirstSpeedIsSent() async {
        let b = FanBench.make()
        defer { b.cleanup() }
        var journalAtFirstSend: Bool?
        b.driver.onSetTarget = { if journalAtFirstSend == nil { journalAtFirstSend = b.journal } }
        await b.backend.applyConfigurationNow(.manual(level: 50))
        #expect(journalAtFirstSend == true, "a crash between the first write and the journal would leave fans forced")
        #expect(b.journal, "the journal stays set while control is active")
        #expect(b.backend.isControlling)
    }

    @Test func aManualLevelSendsOneSpeedPerFan() async {
        let b = FanBench.make()
        defer { b.cleanup() }
        await b.backend.applyConfigurationNow(.manual(level: 50))
        #expect(b.driver.log.filter { $0.hasPrefix("set:") } == ["set:0:5072", "set:1:4000"])
        #expect(b.backend.state.snapshot.isCooling)
        #expect(b.backend.state.snapshot.coolingLevel == 50)
        #expect(b.backend.state.isWorking == false)
    }

    @Test func theCurveFollowsTheTemperatureAndSendsOnlyWhatChanged() async {
        let b = FanBench.make(soc: 60)
        defer { b.cleanup() }
        await b.backend.applyConfigurationNow(b.curve)
        #expect(b.driver.count("set:") == 2)
        await b.backend.tick()
        #expect(b.driver.count("set:") == 2, "same temperature, same level: nothing is sent")
        b.temperatures.value = [FanControlTemperatureReading(source: .hottestSoC, celsius: 70)]
        await b.backend.tick()
        #expect(b.driver.count("set:") == 4)
        #expect(b.backend.state.snapshot.coolingLevel == 100)
    }

    @Test func returningToSystemHandsBackAndClosesTheJournalOnConfirmation() async {
        let b = FanBench.make()
        defer { b.cleanup() }
        await b.backend.applyConfigurationNow(.manual(level: 50))
        await b.backend.restoreNow(reason: nil)
        #expect(b.driver.count("auto") == 1)
        #expect(!b.backend.isControlling)
        #expect(!b.journal)
    }

    @Test func theJournalStaysSetWhenTheHelperDoesNotConfirm() async {
        let b = FanBench.make()
        defer { b.cleanup() }
        await b.backend.applyConfigurationNow(.manual(level: 50))
        b.driver.returnOutcome = .unreachable
        await b.backend.restoreNow(reason: nil)
        #expect(b.journal, "an unconfirmed hand-back is retried at the next launch")
        #expect(!b.backend.isControlling)
        #expect(b.backend.state.error == .helperUnavailable)
    }

    @Test func theSystemModeHandsBackWhatIsForcedAndForgetsTheResume() async {
        let b = FanBench.make()
        defer { b.cleanup() }
        b.defaults.set(true, forKey: DefaultsKey.fanControlResume)
        await b.backend.applyConfigurationNow(.manual(level: 50))
        #expect(b.defaults.string(forKey: DefaultsKey.fanControlResumeConfiguration)?.isEmpty == false)
        b.backend.applyConfiguration(FanControlConfiguration(mode: .system, manualLevel: 100, curves: []))
        await b.backend.pendingApply?.value
        #expect(b.driver.count("auto") == 1)
        #expect(b.defaults.string(forKey: DefaultsKey.fanControlResumeConfiguration) == nil)
    }

    // MARK: Every way out ends in automatic

    @Test func stoppingTheFeatureHandsBackNowAndKeepsTheJournalForTheNextLaunch() async {
        let b = FanBench.make()
        defer { b.cleanup() }
        await b.backend.applyConfigurationNow(.manual(level: 50))
        b.backend.stop()
        #expect(b.driver.count("autoNow") == 1)
        #expect(!b.backend.isControlling)
        #expect(b.backend.state.isRunning == false)
        #expect(b.journal, "a blocking send cannot confirm")
    }

    @Test func aStopWithNothingForcedNeverTouchesTheDriver() {
        let b = FanBench.make()
        defer { b.cleanup() }
        b.backend.stop()
        b.backend.stopNow()
        #expect(b.driverRequests.value == 0, "a feature that never ran must not even build the Fans model")
        #expect(b.driver.log.isEmpty)
    }

    @Test func quittingHandsBackSynchronously() async {
        let b = FanBench.make()
        defer { b.cleanup() }
        await b.backend.applyConfigurationNow(.manual(level: 100))
        b.backend.stopNow()
        #expect(b.driver.count("autoNow") == 1)
        #expect(!b.backend.isControlling)
    }

    @Test func goingToSleepHandsBack() async {
        let b = FanBench.make()
        defer { b.cleanup() }
        await b.backend.applyConfigurationNow(.manual(level: 100))
        b.backend.willSleep()
        #expect(b.driver.count("autoNow") == 1)
        #expect(!b.backend.isControlling)
    }

    @Test func seriousThermalPressureHandsBackAtTheNextTick() async {
        let b = FanBench.make()
        defer { b.cleanup() }
        await b.backend.applyConfigurationNow(b.curve)
        b.thermal.value = .serious
        await b.backend.tick()
        #expect(b.driver.count("auto") == 1)
        #expect(!b.backend.isControlling)
        #expect(b.backend.state.snapshot.stopReason == .thermalPressure)
        #expect(!b.journal)
    }

    @Test func theUserCeilingHandsBack() async {
        let b = FanBench.make(soc: 60)
        defer { b.cleanup() }
        b.defaults.set(85.0, forKey: FanControlEngine.ceilingKey)
        await b.backend.applyConfigurationNow(b.curve)
        b.temperatures.value = [FanControlTemperatureReading(source: .hottestSoC, celsius: 86)]
        await b.backend.tick()
        #expect(b.driver.count("auto") == 1)
        #expect(b.backend.state.snapshot.stopReason == .thermalPressure)
    }

    @Test func aSensorThatDisappearsHandsBackOnTheThirdTick() async {
        let b = FanBench.make(soc: 60)
        defer { b.cleanup() }
        await b.backend.applyConfigurationNow(b.curve)
        b.temperatures.value = []
        await b.backend.tick()
        await b.backend.tick()
        #expect(b.backend.isControlling, "two misses are tolerated")
        await b.backend.tick()
        #expect(!b.backend.isControlling)
        #expect(b.backend.state.snapshot.stopReason == .temperatureUnavailable)
        #expect(b.driver.count("auto") == 1)
    }

    @Test func aFanReadThatKeepsFailingHandsBack() async {
        let b = FanBench.make()
        defer { b.cleanup() }
        await b.backend.applyConfigurationNow(.manual(level: 50))
        b.driver.fans = nil
        await b.backend.tick()
        await b.backend.tick()
        #expect(b.backend.isControlling)
        await b.backend.tick()
        #expect(!b.backend.isControlling)
        #expect(b.driver.count("auto") == 1)
    }

    @Test func aHelperThatWentAutomaticByItselfEndsControlWithoutAnotherCommand() async {
        let b = FanBench.make()
        defer { b.cleanup() }
        await b.backend.applyConfigurationNow(b.curve)
        b.driver.isManualActive = false
        b.driver.onManualEnded?("Le helper est repassé en automatique.")
        #expect(!b.backend.isControlling)
        #expect(b.backend.state.snapshot.stopReason == .heartbeatLost)
        #expect(b.driver.count("auto") == 0 && b.driver.count("autoNow") == 0)
        #expect(b.journal, "not confirmed: the next launch hands back again")
    }

    @Test func theHelperForcingAutomaticOnASpeedRequestEndsControlAndClosesTheJournal() async {
        let b = FanBench.make()
        defer { b.cleanup() }
        b.driver.targetOutcome = { _, _ in .forcedAutomatic }
        await b.backend.applyConfigurationNow(.manual(level: 100))
        #expect(!b.backend.isControlling)
        #expect(b.backend.state.snapshot.stopReason == .thermalPressure)
        #expect(!b.journal)
    }

    // MARK: Refusals

    @Test func aRateLimitRefusalIsRetriedAtTheNextTick() async {
        let b = FanBench.make()
        defer { b.cleanup() }
        var first = true
        b.driver.targetOutcome = { fan, rpm in
            if first { first = false; return .rejected(reason: "rateLimited") }
            return .applied(fan: fan, rpm: rpm)
        }
        await b.backend.applyConfigurationNow(.manual(level: 50))
        #expect(b.backend.isControlling, "a rate limit is not a failure")
        #expect(b.driver.count("auto") == 0)
        await b.backend.tick()
        #expect(b.backend.state.snapshot.coolingLevel == 50)
    }

    @Test func anyOtherRefusalHandsBack() async {
        let b = FanBench.make()
        defer { b.cleanup() }
        b.driver.targetOutcome = { _, _ in .rejected(reason: "invalidLimits") }
        await b.backend.applyConfigurationNow(.manual(level: 50))
        #expect(!b.backend.isControlling)
        #expect(b.driver.count("auto") == 1)
        #expect(b.backend.state.error == .controlFailed)
    }

    @Test func aFailedWriteHandsBack() async {
        let b = FanBench.make()
        defer { b.cleanup() }
        b.driver.targetOutcome = { _, _ in .failed(reason: "writeFailed") }
        await b.backend.applyConfigurationNow(.manual(level: 50))
        #expect(!b.backend.isControlling)
        #expect(b.driver.count("auto") == 1)
        #expect(b.backend.state.error == .controlFailed)
    }

    @Test func noAnswerFromTheHelperHandsBackAndReportsIt() async {
        let b = FanBench.make()
        defer { b.cleanup() }
        b.driver.targetOutcome = { _, _ in .unreachable }
        b.driver.returnOutcome = .unreachable
        await b.backend.applyConfigurationNow(.manual(level: 50))
        #expect(!b.backend.isControlling)
        #expect(b.backend.state.error == .helperUnavailable)
        #expect(b.journal)
    }

    @Test func aCurveWhoseSensorDoesNotExistIsRefusedAtOnce() async {
        let b = FanBench.make(soc: nil)
        defer { b.cleanup() }
        await b.backend.applyConfigurationNow(b.curve)
        #expect(!b.backend.isControlling)
        #expect(b.driver.count("set:") == 0, "no fan was ever forced")
        #expect(b.backend.state.error == .controlFailed)
    }

    @Test func aMachineWithNoFanIsRefusedBeforeAnyWrite() async {
        let b = FanBench.make()
        defer { b.cleanup() }
        b.driver.fans = []
        await b.backend.applyConfigurationNow(.manual(level: 50))
        #expect(b.driver.count("set:") == 0)
        #expect(!b.backend.isControlling)
    }

    @Test func anInvalidConfigurationNeverReachesTheDriver() async {
        let b = FanBench.make()
        defer { b.cleanup() }
        b.backend.applyConfiguration(FanControlConfiguration(mode: .manual, manualLevel: 37, curves: []))
        b.backend.applyConfiguration(FanControlConfiguration(mode: .curve, manualLevel: 100, curves: []))
        await b.backend.pendingApply?.value
        #expect(b.driver.log.isEmpty)
        #expect(b.backend.state.error == .controlFailed)
    }

    @Test func nothingMovesWhileTheFeatureIsOff() async {
        let b = FanBench.make(started: false)
        defer { b.cleanup() }
        b.backend.applyConfiguration(.manual(level: 100))
        await b.backend.applyConfigurationNow(.manual(level: 100))
        await b.backend.tick()
        #expect(b.driver.log.isEmpty, "read-only: no connect, no command")
        #expect(!b.journal)
    }

    @Test func withoutAnApprovedHelperNothingIsSentAndTheClickAsksForApproval() async {
        let b = FanBench.make()
        defer { b.cleanup() }
        b.driver.access = .notRegistered
        b.backend.applyConfiguration(.manual(level: 100))
        await b.backend.pendingApply?.value
        #expect(b.driver.count("set:") == 0)
        #expect(b.driver.count("install") == 1, "the click on a card button is the explicit click")
        #expect(b.driver.count("openSettings") == 1)
        #expect(!b.journal)
    }

    @Test func theHelperIsNeverRegisteredByATickOrARefresh() async {
        let b = FanBench.make()
        defer { b.cleanup() }
        b.driver.access = .notRegistered
        await b.backend.tick()
        b.backend.refresh()
        b.backend.panelDidAppear()
        b.backend.panelDidDisappear()
        await b.backend.tick()
        #expect(b.driver.count("install") == 0 && b.driver.count("openSettings") == 0)
    }

    // MARK: Launch recovery and resume

    @Test func theLaunchRecoveryHandsBackAndClosesTheJournal() async {
        let b = FanBench.make(started: false)
        defer { b.cleanup() }
        b.defaults.set(true, forKey: DefaultsKey.fanControlRecoveryNeeded)
        await b.backend.recoverAutomatic()
        #expect(b.driver.log.contains("connect") && b.driver.count("auto") == 1)
        #expect(!b.journal)
    }

    @Test func theLaunchRecoveryWithoutAnApprovedHelperKeepsTheJournalAndSendsNothing() async {
        let b = FanBench.make(started: false)
        defer { b.cleanup() }
        b.defaults.set(true, forKey: DefaultsKey.fanControlRecoveryNeeded)
        b.driver.access = .requiresApproval
        await b.backend.recoverAutomatic()
        #expect(b.driver.log.isEmpty)
        #expect(b.journal)
    }

    @Test func theLaunchRecoveryNeverRegistersNorResumes() async {
        let b = FanBench.make(started: false)
        defer { b.cleanup() }
        b.defaults.set(true, forKey: DefaultsKey.fanControlRecoveryNeeded)
        b.defaults.set(true, forKey: DefaultsKey.fanControlResume)
        b.defaults.set("curve", forKey: DefaultsKey.fanControlMode)
        b.defaults.set(FanControlConfiguration.encodeResume(.manual(level: 100)), forKey: DefaultsKey.fanControlResumeConfiguration)
        b.driver.access = .notRegistered
        b.backend.recoverAtLaunch()
        await Task.yield()
        #expect(b.driver.count("install") == 0 && b.driver.count("set:") == 0)
    }

    @Test func noJournalMeansTheLaunchRecoveryDoesNothingAtAll() {
        let b = FanBench.make(started: false)
        defer { b.cleanup() }
        b.backend.recoverAtLaunch()
        #expect(b.driverRequests.value == 0)
        #expect(b.driver.log.isEmpty)
    }

    @Test func aResumeAsksForTheStoredControlOnlyWhenTheFeatureStartsAndThePersonOptedIn() async {
        let b = FanBench.make(started: false)
        defer { b.cleanup() }
        b.defaults.set(true, forKey: DefaultsKey.fanControlResume)
        b.defaults.set("manual", forKey: DefaultsKey.fanControlMode)
        b.defaults.set(FanControlConfiguration.encodeResume(.manual(level: 50)), forKey: DefaultsKey.fanControlResumeConfiguration)
        #expect(b.driver.log.isEmpty, "nothing before the registry starts the feature")
        b.backend.start()
        await b.backend.pendingApply?.value
        #expect(b.driver.count("set:") == 2)
        #expect(b.backend.isControlling)
    }

    @Test func noResumeWithoutTheOptIn() async {
        let b = FanBench.make(started: false)
        defer { b.cleanup() }
        b.defaults.set(FanControlConfiguration.encodeResume(.manual(level: 50)), forKey: DefaultsKey.fanControlResumeConfiguration)
        b.backend.start()
        await b.backend.pendingApply?.value
        #expect(b.driver.count("set:") == 0)
    }

    // MARK: Snapshot

    @Test func theSnapshotCarriesFansTemperaturesAndAThirdPartyManualMode() async {
        let b = FanBench.make(soc: 61)
        defer { b.cleanup() }
        await b.backend.tick()
        #expect(b.backend.state.snapshot.fans.count == 2)
        #expect(b.backend.state.snapshot.temperatures?.first?.celsius == 61)
        #expect(b.backend.state.error == nil)
        b.driver.fans = [FanDriverFan(index: 0, actualRPM: 5000, minRPM: 2317, maxRPM: 7826, targetRPM: 5000, isManual: true)]
        await b.backend.tick()
        #expect(b.backend.state.error == .alreadyControlled, "somebody else holds the fans: we do not fight over them")
    }

    @Test func noFansAndAnUnreadableSmcAreToldApart() async {
        let b = FanBench.make()
        defer { b.cleanup() }
        b.driver.fans = []
        await b.backend.tick()
        #expect(b.backend.state.error == .noFans)
        b.driver.fans = nil
        await b.backend.tick()
        #expect(b.backend.state.error == .unsupportedHardware)
    }

    @Test func anApprovedButUnreachableHelperIsReported() async {
        let b = FanBench.make()
        defer { b.cleanup() }
        b.driver.isReachable = false
        await b.backend.tick()
        #expect(b.backend.state.error == .helperUnavailable)
        #expect(b.backend.state.accessState == .enabled)
    }
}
