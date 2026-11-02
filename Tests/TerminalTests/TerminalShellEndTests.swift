import AppKit
import Darwin
import Foundation
import Testing
@testable import TerminalFeature

// MARK: Fake control: scripted answers, exact record of every call

private final class FakeControl: ProcessControl, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    var starts: [pid_t: UInt64] = [100: 1000, 200: 2000]
    /// The signal that makes the shell reapable; nil: it never dies.
    var diesOn: Int32?
    var reapAnswer: ReapState?
    /// After this many `startTime` calls on the shell, the pid belongs to another process.
    var shellChangesAfter: Int?
    private var shellStartCalls = 0
    private var dead = false

    var log: [String] { lock.withLock { entries } }

    func signalGroup(_ group: pid_t, _ signal: Int32) { lock.withLock { entries.append("G\(group):\(signal)") } }

    func signalProcess(_ pid: pid_t, _ signal: Int32) {
        lock.withLock {
            entries.append("P\(pid):\(signal)")
            if signal == diesOn { dead = true }
        }
    }

    func startTime(of pid: pid_t) -> UInt64? {
        lock.withLock {
            if pid == 100, let limit = shellChangesAfter {
                shellStartCalls += 1
                if shellStartCalls > limit { return 9999 }
            }
            return starts[pid]
        }
    }

    func reap(_ pid: pid_t) -> ReapState {
        lock.withLock {
            if let reapAnswer { return reapAnswer }
            return dead ? .reaped : .running
        }
    }

    func pause(_ seconds: Double) {}
}

private func fakeTerminator(_ control: FakeControl) -> TerminalShellTerminator {
    var terminator = TerminalShellTerminator()
    terminator.control = control
    terminator.graceTicks = 3
    terminator.killTicks = 3
    return terminator
}

@Suite struct TerminalShellEndSequenceTests {
    @Test func shellAloneGetsOneHangUp() {
        let control = FakeControl()
        let target = fakeTerminator(control).hangUp(shellPid: 100, foregroundGroup: 100)
        #expect(control.log == ["P100:1"])
        #expect(target.foregroundGroup == nil && target.shellStart == 1000)
    }

    @Test func foregroundProgramIsHungUpBeforeTheShell() {
        let control = FakeControl()
        let target = fakeTerminator(control).hangUp(shellPid: 100, foregroundGroup: 200)
        #expect(control.log == ["G200:1", "P100:1"])
        #expect(target.foregroundGroup == 200 && target.foregroundStart == 2000)
    }

    @Test func unreadableOrOddGroupsAreNeverSignalled() {
        let control = FakeControl()
        let terminator = fakeTerminator(control)
        _ = terminator.hangUp(shellPid: 100, foregroundGroup: nil)
        _ = terminator.hangUp(shellPid: 100, foregroundGroup: 0)
        _ = terminator.hangUp(shellPid: 100, foregroundGroup: -5)
        #expect(control.log == ["P100:1", "P100:1", "P100:1"])
    }

    @Test func aShellThatCannotBeIdentifiedIsNotSignalled() {
        let control = FakeControl()
        control.starts[100] = nil
        _ = fakeTerminator(control).hangUp(shellPid: 100, foregroundGroup: nil)
        #expect(control.log.isEmpty)
    }

    @Test func shellThatLeavesOnHangUpIsReapedWithoutKill() {
        let control = FakeControl()
        control.diesOn = SIGHUP
        let terminator = fakeTerminator(control)
        let target = terminator.hangUp(shellPid: 100, foregroundGroup: 200)
        #expect(terminator.settle(target) == .reaped)
        #expect(control.log == ["G200:1", "P100:1"])
    }

    @Test func shellThatIgnoresHangUpGetsKillAfterTheGraceOnTheSameTargets() {
        let control = FakeControl()
        control.diesOn = SIGKILL
        let terminator = fakeTerminator(control)
        let target = terminator.hangUp(shellPid: 100, foregroundGroup: 200)
        #expect(terminator.settle(target) == .killed)
        #expect(control.log == ["G200:1", "P100:1", "G200:9", "P100:9"])
    }

    @Test func recycledPidIsNeverKilled() {
        let control = FakeControl()
        let terminator = fakeTerminator(control)
        let target = terminator.hangUp(shellPid: 100, foregroundGroup: nil)
        control.shellChangesAfter = 0  // from now on pid 100 is somebody else
        #expect(terminator.settle(target) == .identityChanged)
        #expect(control.log == ["P100:1"])
    }

    @Test func recycledGroupLeaderKeepsItsGroupButTheShellStillGetsKilled() {
        let control = FakeControl()
        control.diesOn = SIGKILL
        let terminator = fakeTerminator(control)
        let target = terminator.hangUp(shellPid: 100, foregroundGroup: 200)
        control.starts[200] = 5555  // pid 200 is now another process
        #expect(terminator.settle(target) == .killed)
        #expect(control.log == ["G200:1", "P100:1", "P100:9"])
    }

    @Test func alreadyReapedByAnotherOwnerEndsTheWait() {
        let control = FakeControl()
        control.reapAnswer = .notChild
        let terminator = fakeTerminator(control)
        #expect(terminator.settle(terminator.hangUp(shellPid: 100, foregroundGroup: nil)) == .alreadyGone)
    }

    @Test func unkillableShellIsReportedNotLoopedOn() {
        let control = FakeControl()
        let terminator = fakeTerminator(control)
        #expect(terminator.settle(terminator.hangUp(shellPid: 100, foregroundGroup: nil)) == .stuck)
        #expect(control.log == ["P100:1", "P100:9"])
    }
}

// MARK: Real processes

/// A child we own and nobody else reaps (posix_spawn: no Foundation monitor competes for the wait).
private func spawn(_ script: String) -> pid_t {
    var pid: pid_t = 0
    let words: [String] = ["/bin/sh", "-c", script]
    var argv: [UnsafeMutablePointer<CChar>?] = words.map { strdup($0) }
    argv.append(nil)
    defer { argv.forEach { free($0) } }
    // The test runner may itself run with SIGHUP ignored (nohup, background job) and children inherit that:
    // start from default dispositions so "a plain program dies on SIGHUP" is what is tested.
    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    var defaults = sigset_t()
    sigemptyset(&defaults)
    sigaddset(&defaults, SIGHUP)
    sigaddset(&defaults, SIGTERM)
    posix_spawnattr_setsigdefault(&attributes, &defaults)
    var none = sigset_t()
    sigemptyset(&none)
    posix_spawnattr_setsigmask(&attributes, &none)
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
    let status = posix_spawn(&pid, "/bin/sh", nil, &attributes, argv, environ)
    #expect(status == 0)
    return pid
}

private func waitUntil(_ seconds: Double = 20, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return condition()
}

private func isGone(_ pid: pid_t) -> Bool { kill(pid, 0) == -1 && errno == ESRCH }

private func end(_ pid: pid_t, graceTicks: Int) async -> ShellEndOutcome {
    await withCheckedContinuation { continuation in
        var terminator = TerminalShellTerminator()
        terminator.graceTicks = graceTicks
        terminator.completion = { _, outcome in continuation.resume(returning: outcome) }
        let target = terminator.hangUp(shellPid: pid, foregroundGroup: nil)
        terminator.reap(target)
    }
}

@Suite struct TerminalShellEndRealProcessTests {
    @Test func plainShellProgramLeavesOnHangUpAndIsReaped() async {
        let pid = spawn("exec sleep 60")
        #expect(await waitUntil { TerminalProcessInfo.processName(pid) == "sleep" })
        let outcome = await end(pid, graceTicks: 150)
        #expect(outcome == .reaped)
        #expect(await waitUntil { isGone(pid) })
    }

    @Test func processIgnoringHangUpAndTermIsKilledAndReaped() async {
        let pid = spawn("trap '' HUP TERM; exec sleep 60")
        #expect(await waitUntil { TerminalProcessInfo.processName(pid) == "sleep" })  // the ignore survives the exec
        let outcome = await end(pid, graceTicks: 15)  // 0.3 s of grace
        #expect(outcome == .killed)
        #expect(await waitUntil { isGone(pid) })  // gone from the table: reaped, not left as a zombie
    }

    @Test func aPidThatIsNotOursEndsTheWaitWithoutASignal() async {
        let pid = spawn("exit 0")
        #expect(await waitUntil { kill(pid, 0) == 0 })
        var status: Int32 = 0
        waitpid(pid, &status, 0)  // someone else reaped it
        #expect(await end(pid, graceTicks: 5) == .alreadyGone)
    }
}
