import Foundation
import IslandTestSupport
import Testing
@testable import PortKit

/// Lane W3D, the Spaces half. The hold runs against a FAKE `com.apple.dock` (a stored value), a fake process
/// runner for the Dock restart and fake defaults, so the real Dock and the real preference file are never
/// touched. Covers: the Dock restarts only when the preference really changed, never twice inside the minimum
/// interval, the setting is given back on stop, after a crash (the journal) and at launch, and a user's own
/// choice is never overwritten.
@MainActor
@Suite struct AutoQuitSpacesTests {
    // MARK: Fakes

    /// A fake Dock: its stored `mru-spaces`, the value the running process last read, and a count of restarts.
    final class FakeDock {
        var stored: SpacesRearrangeSetting
        var pid: pid_t = 500
        var writes: [Bool?] = []
        var restarts = 0
        var restartSucceeds = true
        var writeSucceeds = true

        init(stored: SpacesRearrangeSetting = .absent) { self.stored = stored }

        var system: SpacesOrderSystem {
            SpacesOrderSystem(
                read: { [self] in stored },
                write: { [self] value in
                    guard writeSucceeds else { return false }
                    writes.append(value)
                    stored = value.map { $0 ? .on : .off } ?? .absent
                    return true
                },
                restartDock: { [self] in
                    guard restartSucceeds else { return false }
                    restarts += 1
                    pid += 1  // a restarted Dock is a new process
                    return true
                },
                dockPID: { [self] in pid })
        }
    }

    private func hold(_ dock: FakeDock, _ defaults: UserDefaults) -> SpacesOrderHold {
        SpacesOrderHold(defaults: defaults, system: dock.system)
    }

    // MARK: The decision table (pure)

    @Test func theStepsOfTheDecisionTable() {
        typealias S = SpacesOrderSupport
        #expect(S.step(wanted: true, current: .absent, marker: nil) == .hold(marker: "absent"))
        #expect(S.step(wanted: true, current: .on, marker: nil) == .hold(marker: "on"))
        #expect(S.step(wanted: true, current: .off, marker: nil) == .remember, "already fixed by the person: no write, no restart")
        #expect(S.step(wanted: true, current: .off, marker: "absent") == .none)
        #expect(S.step(wanted: true, current: .on, marker: "absent") == .letGo, "the person turned it back on: their choice stands")
        #expect(S.step(wanted: false, current: .off, marker: "absent") == .release(removeKey: true))
        #expect(S.step(wanted: false, current: .off, marker: "on") == .release(removeKey: false))
        #expect(S.step(wanted: false, current: .on, marker: "absent") == .forget, "the person's own value is left alone")
        #expect(S.step(wanted: false, current: .off, marker: "off") == .forget, "it was already off before: nothing is put back")
        #expect(S.step(wanted: false, current: .off, marker: nil) == .none)
        #expect(S.step(wanted: true, current: .unsupported, marker: nil) == .none, "a managed profile is never written over")
        #expect(S.step(wanted: true, current: .unreadable, marker: nil) == .none)
    }

    // MARK: The hold, against the fake Dock

    @Test func turningItOnWritesOnceRestartsTheDockOnceAndSavesWhatToPutBack() {
        PortHostFixture.isolated { defaults in
            let dock = FakeDock(stored: .absent)
            let h = hold(dock, defaults)
            #expect(h.reconcile(wanted: true))
            #expect(dock.stored == .off && dock.writes == [false] && dock.restarts == 1)
            #expect(defaults.string(forKey: DefaultsKey.spacesOrderRestore) == "absent", "the original state is saved")
            #expect(defaults.string(forKey: DefaultsKey.spacesOrderRestartPending) == nil, "no restart is owed afterwards")
        }
    }

    @Test func aSecondSyncChangesNothingAndNeverRestartsTheDockAgain() {
        PortHostFixture.isolated { defaults in
            let dock = FakeDock(stored: .on)
            let h = hold(dock, defaults)
            #expect(h.reconcile(wanted: true))
            #expect(h.reconcile(wanted: true))
            #expect(h.reconcile(wanted: true))
            #expect(dock.writes == [false] && dock.restarts == 1, "idempotent: one write, one restart")
        }
    }

    @Test func aPreferenceThatWasAlreadyOffIsNeverWrittenAndTheDockNeverRestarted() {
        PortHostFixture.isolated { defaults in
            let dock = FakeDock(stored: .off)
            let h = hold(dock, defaults)
            #expect(h.reconcile(wanted: true))
            #expect(dock.writes.isEmpty && dock.restarts == 0, "the value did not change, so the Dock is left alone")
            #expect(defaults.string(forKey: DefaultsKey.spacesOrderRestore) == "off")
            // Letting go puts nothing back: the person had it off before.
            #expect(h.reconcile(wanted: false))
            #expect(dock.stored == .off && dock.writes.isEmpty && dock.restarts == 0)
            #expect(defaults.string(forKey: DefaultsKey.spacesOrderRestore) == nil)
        }
    }

    @Test func turningItOffGivesTheOriginalSettingBack() {
        PortHostFixture.isolated { defaults in
            let missing = FakeDock(stored: .absent)
            let h = hold(missing, defaults)
            #expect(h.reconcile(wanted: true) && h.reconcile(wanted: false))
            #expect(missing.stored == .absent, "the key is removed again: the system default")
            #expect(missing.writes == [false, nil] && missing.restarts == 2)
            #expect(defaults.string(forKey: DefaultsKey.spacesOrderRestore) == nil)
        }
        PortHostFixture.isolated { defaults in
            let on = FakeDock(stored: .on)
            let h = hold(on, defaults)
            #expect(h.reconcile(wanted: true) && h.reconcile(wanted: false))
            #expect(on.stored == .on && on.writes == [false, true])
        }
    }

    @Test func aStopWithNothingOwedTouchesNothing() {
        PortHostFixture.isolated { defaults in
            let dock = FakeDock(stored: .absent)
            let h = hold(dock, defaults)
            #expect(h.restoreForRemoval(), "nothing owed: true")
            #expect(dock.writes.isEmpty && dock.restarts == 0)
        }
    }

    @Test func theKillSwitchPathRestoresWhatTheHoldChanged() {
        PortHostFixture.isolated { defaults in
            let dock = FakeDock(stored: .absent)
            let h = hold(dock, defaults)
            #expect(h.reconcile(wanted: true))
            #expect(h.restoreForRemoval(), "what `stopSpaces` and the quit hook run")
            #expect(dock.stored == .absent && defaults.string(forKey: DefaultsKey.spacesOrderRestore) == nil)
        }
    }

    // MARK: After a crash

    @Test func aCrashWhileHeldIsRecoveredFromTheMarkerAtTheNextLaunch() {
        PortHostFixture.isolated { defaults in
            let dock = FakeDock(stored: .absent)
            #expect(hold(dock, defaults).reconcile(wanted: true))
            // The app dies here: the preference stays off, the marker stays. A new process, a new hold object.
            #expect(SpacesOrderHold.hasPendingRestore)
            let afterRelaunch = hold(dock, defaults)
            #expect(afterRelaunch.restoreForRemoval(), "recoverIfNeeded ends in this when the feature is not wanted")
            #expect(dock.stored == .absent, "the person's setting is back")
            #expect(!SpacesOrderHold.hasPendingRestore)
        }
    }

    @Test func aCrashBetweenTheWriteAndTheRestartLeavesAJournalThatTheNextSyncFinishes() {
        PortHostFixture.isolated { defaults in
            let dock = FakeDock(stored: .absent)
            dock.restartSucceeds = false
            let h = hold(dock, defaults)
            #expect(!h.reconcile(wanted: true), "the restart failed")
            #expect(dock.stored == .off)
            #expect(defaults.string(forKey: DefaultsKey.spacesOrderRestartPending) != nil, "a restart is still owed")
            #expect(SpacesOrderHold.hasPendingRestore)
            dock.restartSucceeds = true
            #expect(h.reconcile(wanted: true), "the next sync only restarts the Dock")
            #expect(dock.writes == [false] && dock.restarts == 1, "no second write, one restart")
            #expect(defaults.string(forKey: DefaultsKey.spacesOrderRestartPending) == nil)
        }
    }

    @Test func aWriteThatFailsLeavesNothingOwedAndNoRestart() {
        PortHostFixture.isolated { defaults in
            let dock = FakeDock(stored: .absent)
            dock.writeSucceeds = false
            let h = hold(dock, defaults)
            #expect(!h.reconcile(wanted: true))
            #expect(dock.stored == .absent && dock.restarts == 0)
            #expect(defaults.string(forKey: DefaultsKey.spacesOrderRestore) == nil, "no marker for a change that never happened")
        }
    }

    @Test func aManagedPreferenceIsNeverWrittenOver() {
        PortHostFixture.isolated { defaults in
            let dock = FakeDock(stored: .unsupported)
            let h = hold(dock, defaults)
            #expect(h.reconcile(wanted: true))
            #expect(dock.writes.isEmpty && dock.restarts == 0 && !SpacesOrderHold.hasPendingRestore)
        }
    }

    @Test func recoveryHasACallerAtLaunchAndTheMarkersAreNeverBackedUp() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/PortKit")
        let bridge = try String(contentsOf: sources.appendingPathComponent("Bridge/PortBridge.swift"), encoding: .utf8)
        let launch = try #require(bridge.range(of: "static func recoverAtLaunch"))
        #expect(bridge[launch.lowerBound...].contains("SpacesOrderHold.recoverIfNeeded()"),
                "PortBridge.recoverAtLaunch settles a marker a crash left")
        let backup = try String(contentsOf: sources.appendingPathComponent("Core/SettingsBackupSupport.swift"), encoding: .utf8)
        #expect(backup.contains("DefaultsKey.spacesOrderRestore") && backup.contains("DefaultsKey.spacesOrderRestartPending"))
    }

    // MARK: The guarded restart

    private final class Clock: @unchecked Sendable { var now = Date(timeIntervalSinceReferenceDate: 5_000) }

    private func guarded(interval: TimeInterval = 15, clock: Clock, ran: Box<Int>, retries: Box<[TimeInterval]>,
                         succeeds: Box<Bool> = Box(true)) -> SpacesDockRestartGuard {
        SpacesDockRestartGuard(interval: interval, now: { clock.now },
                               run: { ran.value += 1; return succeeds.value },
                               scheduleRetry: { retries.value.append($0) })
    }

    @Test func theFirstRestartRunsAndASecondInsideTheIntervalIsRefused() {
        let clock = Clock(), ran = Box(0), retries = Box<[TimeInterval]>([])
        let g = guarded(clock: clock, ran: ran, retries: retries)
        #expect(g.restart() && ran.value == 1)
        clock.now.addTimeInterval(5)
        #expect(!g.restart() && ran.value == 1, "nothing ran: the Dock does not flap")
        #expect(retries.value.count == 1 && retries.value[0] > 10 && retries.value[0] < 16,
                "one retry, for when the interval is over")
        clock.now.addTimeInterval(1)
        #expect(!g.restart() && ran.value == 1 && retries.value.count == 1, "still one retry, not one per refusal")
    }

    @Test func afterTheIntervalARestartRunsAgain() {
        let clock = Clock(), ran = Box(0), retries = Box<[TimeInterval]>([])
        let g = guarded(clock: clock, ran: ran, retries: retries)
        #expect(g.restart())
        clock.now.addTimeInterval(15)
        #expect(g.restart() && ran.value == 2)
        clock.now.addTimeInterval(2)
        #expect(!g.restart())
        #expect(retries.value.count == 1, "the retry flag was re-armed by the restart that ran")
    }

    @Test func aFailedRestartDoesNotCountAsOne() {
        let clock = Clock(), ran = Box(0), retries = Box<[TimeInterval]>([]), ok = Box(false)
        let g = guarded(clock: clock, ran: ran, retries: retries, succeeds: ok)
        #expect(!g.restart() && ran.value == 1)
        ok.value = true
        #expect(g.restart() && ran.value == 2, "not held back by an attempt that failed")
        #expect(retries.value.isEmpty)
    }

    @Test func aQuickOnOffToggleOnTheHoldRestartsTheDockOnceAndKeepsTheJournalForTheRetry() {
        PortHostFixture.isolated { defaults in
            let dock = FakeDock(stored: .absent)
            let clock = Clock(), ran = Box(0), retries = Box<[TimeInterval]>([])
            let g = SpacesDockRestartGuard(interval: 15, now: { clock.now },
                                           run: { ran.value += 1; return dock.system.restartDock() },
                                           scheduleRetry: { retries.value.append($0) })
            let system = SpacesOrderSystem(read: dock.system.read, write: dock.system.write,
                                           restartDock: { g.restart() }, dockPID: dock.system.dockPID)
            let h = SpacesOrderHold(defaults: defaults, system: system)
            #expect(h.reconcile(wanted: true))
            clock.now.addTimeInterval(3)
            #expect(!h.reconcile(wanted: false), "the second restart is refused inside the interval")
            #expect(dock.restarts == 1, "the Dock restarted once, not twice")
            #expect(retries.value.count == 1)
            #expect(defaults.string(forKey: DefaultsKey.spacesOrderRestartPending) != nil, "a restart is still owed")
            // The retry fires after the interval: the same sync finishes it.
            clock.now.addTimeInterval(15)
            #expect(h.reconcile(wanted: false))
            #expect(dock.restarts == 2 && dock.stored == .absent)
            #expect(defaults.string(forKey: DefaultsKey.spacesOrderRestartPending) == nil)
        }
    }

    @Test func theMinimumIntervalIsLongEnoughToMatter() {
        #expect(SpacesDockRestartGuard.minimumInterval >= 10)
    }
}
