import Foundation
import IslandKit
import IslandUI
import Testing
@testable import PortKit

/// The pure decisions of the energy lane: closed-lid safety policy, the sudoers rule, keep-awake end time and
/// automation, Bluetooth and microphone restore rules. No pmset, sudo, IOPM, Bluetooth or CoreAudio.
@MainActor
@Suite struct EnergyPolicyTests {
    // MARK: Closed-lid safety policy

    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func verdict(onBattery: Bool = false, percent: Int? = 80, thermal: ProcessInfo.ThermalState = .nominal,
                         since: Date? = nil) -> ClamshellSafetyPolicy.Violation? {
        ClamshellSafetyPolicy.violation(onBattery: onBattery, batteryPercent: percent, thermalState: thermal,
                                        activeSince: since, now: now)
    }

    @Test func plugInAndCoolMeansNoViolation() {
        #expect(verdict() == nil)
        #expect(verdict(percent: 3) == nil, "plugged in: the level does not matter")
        #expect(verdict(percent: nil) == nil, "a desktop Mac has no battery")
    }

    @Test func underTwentyPercentOnBatteryEndsTheMode() {
        #expect(verdict(onBattery: true, percent: 19) == .lowBattery(percent: 19))
        #expect(verdict(onBattery: true, percent: 1) == .lowBattery(percent: 1))
        #expect(verdict(onBattery: true, percent: 20) == nil, "the threshold is strict")
        #expect(verdict(onBattery: true, percent: 80) == nil)
    }

    @Test func anUnreadableLevelOnBatteryFailsClosed() {
        #expect(verdict(onBattery: true, percent: nil) == .lowBattery(percent: 0))
    }

    @Test func aSeriousOrCriticalThermalStateEndsTheMode() {
        #expect(verdict(thermal: .serious) == .hot)
        #expect(verdict(thermal: .critical) == .hot)
        #expect(verdict(thermal: .fair) == nil)
        #expect(verdict(thermal: .nominal) == nil)
    }

    @Test func heatBeatsBatteryBeatsDuration() {
        let longAgo = now.addingTimeInterval(-ClamshellSafetyPolicy.maximumDuration - 1)
        #expect(verdict(onBattery: true, percent: 5, thermal: .critical, since: longAgo) == .hot)
        #expect(verdict(onBattery: true, percent: 5, since: longAgo) == .lowBattery(percent: 5))
        #expect(verdict(since: longAgo) == .tooLong)
    }

    @Test func theDurationCapIsEightHoursFromWhenSleepWasReallyDisabled() {
        let cap = ClamshellSafetyPolicy.maximumDuration
        #expect(cap == 8 * 3600)
        #expect(verdict(since: now.addingTimeInterval(-cap + 1)) == nil)
        #expect(verdict(since: now.addingTimeInterval(-cap)) == .tooLong)
        #expect(verdict(since: nil) == nil, "before the mode is on there is no clock to read")
    }

    @Test func everyViolationHasAFrenchMessage() {
        #expect(ClamshellSafetyPolicy.Violation.lowBattery(percent: 12).message
            == "Mode capot fermé arrêté : batterie à 12 % sur batterie (seuil 20 %).")
        #expect(ClamshellSafetyPolicy.Violation.hot.message == "Mode capot fermé arrêté : le Mac chauffe trop.")
        #expect(ClamshellSafetyPolicy.Violation.tooLong.message
            == "Mode capot fermé arrêté : durée maximale de 8 h atteinte.")
    }

    // MARK: Sudoers rule

    @Test func theRuleIsGrantedByUidAndLimitedToPmsetDisablesleep() {
        let rule = SudoersSupport.clamshellRule(uid: 501)
        #expect(rule == "#501 ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 1, /usr/bin/pmset disablesleep 0")
        #expect(ClosedLidRule.isValid(rule, uid: 501))
        #expect(Sudoers.rulePath == "/etc/sudoers.d/macisland-clamshell")
    }

    @Test func theValidatorRefusesAnythingButTheExactRuleOfThatUid() {
        let good = SudoersSupport.clamshellRule(uid: 501)
        #expect(!ClosedLidRule.isValid(good, uid: 502), "another uid")
        #expect(!ClosedLidRule.isValid(good + "\n#501 ALL=(root) NOPASSWD: ALL", uid: 501), "a second line")
        #expect(!ClosedLidRule.isValid(good + "'; rm -rf / #", uid: 501), "a quote would close the shell string")
        #expect(!ClosedLidRule.isValid(good.replacingOccurrences(of: "disablesleep 0", with: "disablesleep *"), uid: 501))
        #expect(!ClosedLidRule.isValid("alice ALL=(root) NOPASSWD: \(ClosedLidRule.commands)", uid: 501), "a username")
        #expect(!ClosedLidRule.isValid("#501 ALL=(ALL) NOPASSWD: \(ClosedLidRule.commands)", uid: 501))
        #expect(!ClosedLidRule.isValid("#501 ALL=(root) NOPASSWD: /usr/bin/pmset", uid: 501), "pmset without the argument pin")
        #expect(!ClosedLidRule.isValid("", uid: 501))
    }

    @Test func theRuleNamesNoOtherBinaryNorWildcard() {
        let rule = SudoersSupport.clamshellRule(uid: 0)
        #expect(!rule.contains("*") && !rule.contains(";") && !rule.contains("'") && !rule.contains("\n"))
        let commands = rule.components(separatedBy: "NOPASSWD: ")[1].components(separatedBy: ", ")
        #expect(commands == ["/usr/bin/pmset disablesleep 1", "/usr/bin/pmset disablesleep 0"])
    }

    @Test func aPmsetReportIsReadForSleepDisabled() {
        #expect(SudoersSupport.sleepDisabled(inPmsetOutput: " SleepDisabled\t\t1\n"))
        #expect(!SudoersSupport.sleepDisabled(inPmsetOutput: " SleepDisabled\t\t0\n"))
        #expect(!SudoersSupport.sleepDisabled(inPmsetOutput: " sleep 1\n"))
    }

    // MARK: Display sleep seed

    @Test func theDisplaySleepKeyIsSeededOnceFromOurOldChoice() {
        PortHostFixture.isolated { defaults in
            // Nothing stored: our module let the display sleep, so the ported key says "allow".
            EnergyMerge.seedDisplaySleep(in: defaults, stored: [:])
            #expect(defaults.bool(forKey: DefaultsKey.keepAwakeAllowDisplaySleep))
            // Once: a later run does not overwrite what the person chose after.
            defaults.set(false, forKey: DefaultsKey.keepAwakeAllowDisplaySleep)
            EnergyMerge.seedDisplaySleep(in: defaults, stored: [:])
            #expect(!defaults.bool(forKey: DefaultsKey.keepAwakeAllowDisplaySleep))
        }
    }

    @Test func ourOldPreventDisplaySleepChoiceCarriesOver() {
        PortHostFixture.isolated { defaults in
            EnergyMerge.seedDisplaySleep(in: defaults, stored: ["keepAwakePreventDisplaySleep": true])
            #expect(!defaults.bool(forKey: DefaultsKey.keepAwakeAllowDisplaySleep), "prevent -> do not allow")
        }
    }

    @Test func aPortedChoiceAlreadyStoredIsNeverOverwritten() {
        PortHostFixture.isolated { defaults in
            defaults.set(false, forKey: DefaultsKey.keepAwakeAllowDisplaySleep)
            EnergyMerge.seedDisplaySleep(in: defaults, stored: [DefaultsKey.keepAwakeAllowDisplaySleep: false])
            #expect(!defaults.bool(forKey: DefaultsKey.keepAwakeAllowDisplaySleep))
            #expect(defaults.bool(forKey: EnergyMerge.seededKey))
        }
    }

    // MARK: Keep Awake end time and automation

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = day; c.hour = hour; c.minute = minute
        return Calendar.current.date(from: c)!
    }

    @Test func anEndTimeLaterTodayLandsToday() {
        let end = KeepAwakeAutomationSupport.resolvedUntilDate(picked: date(1, 18, 30), now: date(1, 9, 0))
        #expect(end == date(1, 18, 30))
    }

    @Test func anEndTimeAlreadyPassedRollsToTomorrow() {
        let end = KeepAwakeAutomationSupport.resolvedUntilDate(picked: date(1, 8, 15), now: date(1, 9, 0))
        #expect(end == date(2, 8, 15))
        #expect(end > date(1, 9, 0))
    }

    @Test func theMinuteWeAreInRollsToTomorrowNotToNow() {
        let end = KeepAwakeAutomationSupport.resolvedUntilDate(picked: date(1, 9, 0), now: date(1, 9, 0))
        #expect(end == date(2, 9, 0))
    }

    private typealias Condition = KeepAwakeAutomationCondition

    @Test func theThreeAutomationTriggersMatchOnlyWhenEnabledAndTrue() {
        let all = KeepAwakeAutomationSupport.matchingConditions(
            externalDisplayEnabled: true, externalDisplayConnected: true, powerEnabled: true, connectedToPower: true,
            runningAppsEnabled: true, selectedAppsRunning: true)
        #expect(all == [.externalDisplay, .power, .runningApps])
        let disabled = KeepAwakeAutomationSupport.matchingConditions(
            externalDisplayEnabled: false, externalDisplayConnected: true, powerEnabled: false, connectedToPower: true,
            runningAppsEnabled: false, selectedAppsRunning: true)
        #expect(disabled.isEmpty, "a trigger that is switched off never matches")
        let onlyPower = KeepAwakeAutomationSupport.matchingConditions(
            externalDisplayEnabled: true, externalDisplayConnected: false, powerEnabled: true, connectedToPower: true,
            runningAppsEnabled: true, selectedAppsRunning: false)
        #expect(onlyPower == [.power])
    }

    @Test func anAppTriggerWithNoAppSelectedIsNotEnabled() {
        let enabled = KeepAwakeAutomationSupport.enabledConditions(
            externalDisplayEnabled: false, powerEnabled: true, runningAppsEnabled: true, hasSelectedApps: false)
        #expect(enabled == [.power])
        #expect(!KeepAwakeAutomationSupport.selectedAppsAreRunning(selectedBundleIDs: [], runningBundleIDs: ["a"]))
        #expect(KeepAwakeAutomationSupport.selectedAppsAreRunning(selectedBundleIDs: ["a", "b"], runningBundleIDs: ["z", "b"]))
    }

    @Test func anyNeedsOneConditionAndAllNeedsEveryEnabledOne() {
        let enabled: Set<Condition> = [.power, .externalDisplay]
        #expect(KeepAwakeAutomationSupport.conditionsSatisfied(matching: [.power], enabled: enabled, requireAll: false))
        #expect(!KeepAwakeAutomationSupport.conditionsSatisfied(matching: [.power], enabled: enabled, requireAll: true))
        #expect(KeepAwakeAutomationSupport.conditionsSatisfied(matching: enabled, enabled: enabled, requireAll: true))
        #expect(!KeepAwakeAutomationSupport.conditionsSatisfied(matching: [], enabled: enabled, requireAll: false))
    }

    @Test func theAutomationActionTableIsActivateOnlyWhenIdleAndDeactivateOnlyItsOwnSession() {
        typealias A = KeepAwakeAutomationSupport
        // Wanted, idle -> start. Wanted, running -> nothing.
        #expect(A.action(featureAvailable: true, matchingConditions: [.power], enabledConditions: [.power],
                         sessionActive: false, automaticSessionActive: false) == .activate)
        #expect(A.action(featureAvailable: true, matchingConditions: [.power], enabledConditions: [.power],
                         sessionActive: true, automaticSessionActive: false) == .none)
        // No longer wanted: only the automatic session is ended, a manual one stays.
        #expect(A.action(featureAvailable: true, matchingConditions: [], enabledConditions: [.power],
                         sessionActive: true, automaticSessionActive: true) == .deactivate)
        #expect(A.action(featureAvailable: true, matchingConditions: [], enabledConditions: [.power],
                         sessionActive: true, automaticSessionActive: false) == .none)
        // The registry says no (switch, kill switch): never start, and end the automatic session.
        #expect(A.action(featureAvailable: false, matchingConditions: [.power], enabledConditions: [.power],
                         sessionActive: false, automaticSessionActive: false) == .none)
        #expect(A.action(featureAvailable: false, matchingConditions: [.power], enabledConditions: [.power],
                         sessionActive: true, automaticSessionActive: true) == .deactivate)
    }

    @Test func lidSleepIsRefusedByALidSpecificAssertion() {
        #expect(KeepAwakeAutomationSupport.lidSleepIsAllowed(systemAllowsSleep: true, assertions: []))
        #expect(!KeepAwakeAutomationSupport.lidSleepIsAllowed(systemAllowsSleep: false, assertions: []))
        #expect(!KeepAwakeAutomationSupport.lidSleepIsAllowed(systemAllowsSleep: nil, assertions: nil))
        #expect(!KeepAwakeAutomationSupport.lidSleepIsAllowed(
            systemAllowsSleep: true, assertions: [["AssertType": "PreventSystemSleep", "AppliesOnLidClose": true]]))
        #expect(KeepAwakeAutomationSupport.lidSleepIsAllowed(
            systemAllowsSleep: true, assertions: [["AssertType": "PreventUserIdleSystemSleep", "AppliesOnLidClose": true]]),
                "an ordinary idle-sleep assertion must not defeat a closed-lid battery cutoff")
    }

    // MARK: Bluetooth restore rules

    @Test func bluetoothAlreadyOffIsNeverSwitchedBackOn() {
        #expect(BluetoothSleepSupport.sleepPlan(isPoweredOn: false, restoresOnWake: true)
            == .init(powersOff: false, owesRestore: false))
        #expect(BluetoothSleepSupport.sleepPlan(isPoweredOn: true, restoresOnWake: true)
            == .init(powersOff: true, owesRestore: true))
        #expect(BluetoothSleepSupport.sleepPlan(isPoweredOn: true, restoresOnWake: false)
            == .init(powersOff: true, owesRestore: false), "the person chose to stay off after wake")
    }

    @Test func aRestoreOwedIsPaidUnlessThePersonSwitchedBluetoothOnThemselves() {
        #expect(BluetoothSleepSupport.restores(owesRestore: true, isPoweredOn: false))
        #expect(!BluetoothSleepSupport.restores(owesRestore: true, isPoweredOn: true))
        #expect(!BluetoothSleepSupport.restores(owesRestore: false, isPoweredOn: false))
        var read = false
        _ = BluetoothSleepSupport.restores(owesRestore: false, isPoweredOn: { read = true; return false }())
        #expect(!read, "the controller is read only when a restore is owed")
    }

    // MARK: Microphone restore rules

    @Test func anUnmuteTouchesOnlyTheDevicesThisAppMuted() {
        #expect(MicMuteSupport.restoreTargets(recorded: ["a"], present: ["a", "b"]) == ["a"])
        #expect(MicMuteSupport.restoreTargets(recorded: [], present: ["a", "b"]).isEmpty, "all were muted by the person")
        #expect(MicMuteSupport.restoreTargets(recorded: nil, present: ["a", "b"]) == ["a", "b"], "no record: never leave one muted")
    }

    @Test func aDeviceUnpluggedWhileMutedStaysOursToRelease() {
        #expect(MicMuteSupport.absentClaims(recorded: ["a", "b"], present: ["a"]) == ["b"])
        #expect(MicMuteSupport.absentClaims(recorded: nil, present: ["a"]).isEmpty)
    }

    @Test func aSavedLevelOfZeroIsNeverRestoredAsSilence() {
        #expect(!MicMuteSupport.shouldSaveVolume(0))
        #expect(!MicMuteSupport.shouldSaveVolume(nil))
        #expect(MicMuteSupport.shouldSaveVolume(0.4))
        #expect(MicMuteSupport.volumeToRestore(uid: "a", saved: ["a": 0.0], legacy: 0) == MicMuteSupport.fallbackVolume)
        #expect(MicMuteSupport.volumeToRestore(uid: "a", saved: ["a": 0.6], legacy: 0) == 0.6)
    }

    @Test func theAppsOwnAggregateDevicesAreNeverMuted() {
        #expect(MicMuteSupport.isOwnDevice(name: "Mac Island Mixer"))
        #expect(!MicMuteSupport.isOwnDevice(name: "MacBook Pro Microphone"))
    }

    // MARK: Music block

    @Test func onlyAFreshMediaKeyWithNoNewerGestureBlocksALaunch() {
        #expect(MusicLaunchSupport.shouldBlockLaunch(now: 100, lastTriggerAt: 99, secondsSinceUserGesture: 30))
        #expect(!MusicLaunchSupport.shouldBlockLaunch(now: 100, lastTriggerAt: nil, secondsSinceUserGesture: 30))
        #expect(!MusicLaunchSupport.shouldBlockLaunch(now: 100, lastTriggerAt: 90, secondsSinceUserGesture: 30), "expired")
        #expect(!MusicLaunchSupport.shouldBlockLaunch(now: 100, lastTriggerAt: 99, secondsSinceUserGesture: 0.5),
                "a click after the key wins: the person opened it")
    }

    // MARK: The island says what is going on

    @Test func theIslandIndicatorsAreFrenchAndOnlyPresentWhileTrue() {
        #expect(EnergyIndicators.indicators(closedLidActive: false, sleepRestoreNeeded: false, stopReason: nil,
                                            micMuted: false).isEmpty)
        let lid = EnergyIndicators.indicators(closedLidActive: true, sleepRestoreNeeded: false, stopReason: nil,
                                              micMuted: false)
        #expect(lid.map(\.text) == ["Mode capot fermé actif"])
        #expect(lid.first?.lifetime == nil, "stays while the mode is on")
        let mic = EnergyIndicators.indicators(closedLidActive: false, sleepRestoreNeeded: false, stopReason: nil,
                                              micMuted: true)
        #expect(mic.map(\.text) == ["Micro coupé"])
        let stuck = EnergyIndicators.indicators(closedLidActive: false, sleepRestoreNeeded: true, stopReason: nil,
                                                micMuted: false)
        #expect(stuck.first?.status == .danger)
        let stopped = EnergyIndicators.indicators(closedLidActive: false, sleepRestoreNeeded: false,
                                                  stopReason: .hot, micMuted: false)
        #expect(stopped.first?.text == ClamshellSafetyPolicy.Violation.hot.message)
        #expect(stopped.first?.lifetime == 12)
    }

    @Test func aSessionEndNoticeNamesOnlyTimerAndBattery() {
        #expect(EnergyIndicators.endNotice(minutesWereSet: false, battery: true) == "Éveil arrêté : batterie faible")
        #expect(EnergyIndicators.endNotice(minutesWereSet: true, battery: false) == "Éveil terminé")
        #expect(EnergyIndicators.endNotice(minutesWereSet: false, battery: false) == nil)
    }

    @MainActor @Test func theBridgePostsWhatIsOnAndWithdrawsWhatIsNot() {
        let posted = Box<[String]>([])
        let withdrawn = Box<[String]>([])
        let bridge = EnergyIslandBridge(post: { activity, ttl in
            posted.value.append(activity.id + (ttl == nil ? "" : "+ttl"))
        }, withdraw: { withdrawn.value.append($0) })
        bridge.update(closedLid: true)
        #expect(posted.value == ["energy.closedLid"])
        #expect(Set(withdrawn.value) == [EnergyIndicators.restoreID, EnergyIndicators.stoppedID, EnergyIndicators.micID])
        bridge.update(micMuted: true)
        #expect(posted.value.contains("energy.micMuted"))
        withdrawn.value = []
        bridge.update(closedLid: false)
        #expect(withdrawn.value.contains(EnergyIndicators.closedLidID))
    }

    @MainActor @Test func theStopNoticeIsPostedOncePerReason() {
        let posted = Box<[String]>([])
        let bridge = EnergyIslandBridge(post: { activity, _ in posted.value.append(activity.id) }, withdraw: { _ in })
        bridge.update(stopReason: .some(.tooLong))
        bridge.update(micMuted: true)  // an unrelated update must not repost the notice
        #expect(posted.value.filter { $0 == EnergyIndicators.stoppedID }.count == 1)
        bridge.update(stopReason: .some(nil))
        bridge.update(stopReason: .some(.hot))
        #expect(posted.value.filter { $0 == EnergyIndicators.stoppedID }.count == 2)
    }
}
