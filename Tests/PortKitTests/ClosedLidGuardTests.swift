import Foundation
import Testing
@testable import PortKit

/// `pmset disablesleep 1` must not outlive a crashed app: while lid sleep is off a tiny child waits on a pipe the app
/// owns and gives it back when the pipe closes. The state machine, the guard with a fake launcher, and a real
/// `/bin/sh` child whose cleanup is a harmless `touch` (the production cleanup, `sudo -n pmset`, is never run here).
@Suite(.serialized) struct ClosedLidGuardTests {
    // MARK: The pure state machine

    @Test func aDisableStartsOneChildAndARestoreReleasesIt() {
        var state = ClosedLidGuardState()
        #expect(state.phase == .idle)
        #expect(state.lidSleepRestored() == .none, "nothing to release before anything was disabled")
        #expect(state.lidSleepDisabled() == .start)
        #expect(state.phase == .armed)
        #expect(state.lidSleepDisabled() == .none, "a second disable never starts a second child")
        #expect(state.lidSleepRestored() == .release)
        #expect(state.phase == .idle)
        #expect(state.lidSleepRestored() == .none)
    }

    @Test func aChildThatEndedOnItsOwnLetsTheNextDisableStartANewOne() {
        var state = ClosedLidGuardState()
        _ = state.lidSleepDisabled()
        state.childEnded()
        #expect(state.phase == .idle)
        #expect(state.lidSleepDisabled() == .start)
    }

    // MARK: The guard with a fake launcher

    private final class FakeChild: ClosedLidGuardChild, @unchecked Sendable {
        private let lock = NSLock()
        private var released = 0
        let onExit: @Sendable () -> Void
        init(onExit: @escaping @Sendable () -> Void) { self.onExit = onExit }
        var releaseCount: Int { lock.lock(); defer { lock.unlock() }; return released }
        func release() { lock.lock(); released += 1; lock.unlock() }
    }

    private final class FakeLauncher: ClosedLidGuardLaunching, @unchecked Sendable {
        private let lock = NSLock()
        private var launched: [FakeChild] = []
        var fails = false
        var children: [FakeChild] { lock.lock(); defer { lock.unlock() }; return launched }

        func launch(onExit: @escaping @Sendable () -> Void) -> ClosedLidGuardChild? {
            if fails { return nil }
            let child = FakeChild(onExit: onExit)
            lock.lock(); launched.append(child); lock.unlock()
            return child
        }
    }

    @Test func theGuardIsStartedWhenClosedLidIsEnabledAndTheStartIsOnlyOnce() {
        let launcher = FakeLauncher()
        let guardian = ClosedLidGuard(launcher: launcher)
        #expect(!guardian.isArmed && launcher.children.isEmpty, "nothing runs before lid sleep is disabled")
        guardian.sleepStateChanged(disabled: true)
        guardian.sleepStateChanged(disabled: true)  // the 30 s probe re-applies the same state
        #expect(guardian.isArmed)
        #expect(launcher.children.count == 1)
    }

    @Test func aNormalRestoreReleasesTheChildAndANewEnableStartsAnother() {
        let launcher = FakeLauncher()
        let guardian = ClosedLidGuard(launcher: launcher)
        guardian.sleepStateChanged(disabled: true)
        guardian.sleepStateChanged(disabled: false)
        #expect(!guardian.isArmed)
        #expect(launcher.children[0].releaseCount == 1, "the pipe is closed on a normal restore")
        guardian.sleepStateChanged(disabled: false)
        #expect(launcher.children[0].releaseCount == 1, "released once")
        guardian.sleepStateChanged(disabled: true)
        #expect(launcher.children.count == 2)
        #expect(launcher.children[1].releaseCount == 0)
    }

    @Test func aRestoreWithNoGuardTouchesNothing() {
        let launcher = FakeLauncher()
        let guardian = ClosedLidGuard(launcher: launcher)
        guardian.sleepStateChanged(disabled: false)
        #expect(launcher.children.isEmpty && !guardian.isArmed)
    }

    @Test func aChildThatCannotStartDoesNotLeaveTheGuardArmedAndTheNextEnableRetries() {
        let launcher = FakeLauncher()
        launcher.fails = true
        let guardian = ClosedLidGuard(launcher: launcher)
        guardian.sleepStateChanged(disabled: true)
        #expect(!guardian.isArmed)
        launcher.fails = false
        guardian.sleepStateChanged(disabled: true)
        #expect(guardian.isArmed && launcher.children.count == 1)
    }

    @Test func aLateExitReportOfAnOldChildNeverDisarmsTheCurrentOne() {
        let launcher = FakeLauncher()
        let guardian = ClosedLidGuard(launcher: launcher)
        guardian.sleepStateChanged(disabled: true)
        let old = launcher.children[0]
        guardian.sleepStateChanged(disabled: false)
        guardian.sleepStateChanged(disabled: true)
        old.onExit()  // the old child's termination handler, running late
        #expect(guardian.isArmed, "the new child is still the guard")
        guardian.sleepStateChanged(disabled: false)
        #expect(launcher.children[1].releaseCount == 1, "and it is still the one that gets released")
    }

    @Test func aChildKilledWhileArmedLetsTheNextEnableStartANewOne() {
        let launcher = FakeLauncher()
        let guardian = ClosedLidGuard(launcher: launcher)
        guardian.sleepStateChanged(disabled: true)
        launcher.children[0].onExit()
        #expect(!guardian.isArmed)
        guardian.sleepStateChanged(disabled: true)
        #expect(launcher.children.count == 2)
    }

    // MARK: The real shell child (harmless cleanup)

    private func marker() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("mis-lid-\(UUID().uuidString)")
    }

    private func waitUntil(_ seconds: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return condition()
    }

    private func launchReal(marker: URL, onExit: @escaping @Sendable () -> Void) throws -> ShellClosedLidGuardChild {
        let launcher = ShellClosedLidGuardLauncher(cleanup: ["/usr/bin/touch", marker.path])
        return try #require(launcher.launch(onExit: onExit) as? ShellClosedLidGuardChild)
    }

    @Test func whenTheAppDiesTheChildRunsItsCleanup() throws {
        let file = marker(); defer { try? FileManager.default.removeItem(at: file) }
        let exited = DispatchSemaphore(value: 0)
        let child = try launchReal(marker: file) { exited.signal() }
        #expect(!FileManager.default.fileExists(atPath: file.path), "it waits while the app is alive")
        child.abandon()  // the kernel closing the pipe when the app dies, no line written
        #expect(exited.wait(timeout: .now() + 120) == .success)
        #expect(FileManager.default.fileExists(atPath: file.path), "the cleanup ran: lid sleep is given back")
    }

    @Test func aNormalRestoreMakesTheChildStandDownWithoutItsCleanup() throws {
        let file = marker(); defer { try? FileManager.default.removeItem(at: file) }
        let exited = DispatchSemaphore(value: 0)
        let child = try launchReal(marker: file) { exited.signal() }
        child.release()
        #expect(exited.wait(timeout: .now() + 120) == .success, "the child exits once released")
        #expect(!FileManager.default.fileExists(atPath: file.path),
                "no late cleanup that could undo a new enable")
    }

    @Test func releasingAChildThatWasKilledOrAlreadyReleasedIsHarmless() throws {
        let file = marker(); defer { try? FileManager.default.removeItem(at: file) }
        let exited = DispatchSemaphore(value: 0)
        let child = try launchReal(marker: file) { exited.signal() }
        kill(child.processIdentifier, SIGKILL)  // somebody killed the guard child
        #expect(exited.wait(timeout: .now() + 120) == .success)
        child.release()  // a write to the dead child: an error, never SIGPIPE for the app
        child.release()  // and a second call does nothing
        child.abandon()
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    // MARK: Contracts

    @Test func theProductionCleanupIsExactlyTheCommandTheSudoersRulePermits() {
        #expect(ShellClosedLidGuardLauncher.cleanupCommand == ["/usr/bin/sudo", "-n", "/usr/bin/pmset", "disablesleep", "0"])
        #expect(ClosedLidRule.commands.contains("/usr/bin/pmset disablesleep 0"))
        let arguments = ShellClosedLidGuardLauncher.arguments(cleanup: ShellClosedLidGuardLauncher.cleanupCommand)
        #expect(Array(arguments.prefix(3)) == ["-c", "IFS= read -r _ && exit 0; exec \"$@\"", "sh"], "fixed script, nothing interpolated")
        #expect(Array(arguments.dropFirst(3)) == ShellClosedLidGuardLauncher.cleanupCommand)
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: PortSourceScrubTests.repoRoot.appendingPathComponent(path), encoding: .utf8)
    }

    @Test func everyPmsetWriteIsReportedToTheGuardAndTheAdminRestoreUsesTheAbsolutePath() throws {
        let text = try source("Sources/PortKit/Services/ShellSupport.swift")
        let code = text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        #expect(code.contains { $0.contains("ClosedLidGuard.shared.sleepStateChanged(disabled: on)") })
        #expect(code.contains { $0.contains("ClosedLidGuard.shared.sleepStateChanged(disabled: false)") },
                "the administrator restore stands the guard down too")
        #expect(code.contains { $0.contains("AdminShell.run(\"/usr/bin/pmset disablesleep 0\"") })
        #expect(!code.contains { $0.contains("AdminShell.run(\"pmset ") }, "a bare `pmset` is resolved through PATH")
    }
}
