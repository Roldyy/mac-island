import Darwin
import Foundation

/// The system calls the terminator makes, behind one door so a test can script them and read the exact sequence.
protocol ProcessControl: Sendable {
    func signalGroup(_ group: pid_t, _ signal: Int32)
    func signalProcess(_ pid: pid_t, _ signal: Int32)
    /// When the process started (microseconds since the epoch); nil when no such process exists.
    func startTime(of pid: pid_t) -> UInt64?
    func reap(_ pid: pid_t) -> ReapState
    func pause(_ seconds: Double)
}

enum ReapState: Equatable, Sendable {
    case running
    case reaped
    /// Not our child (already reaped by someone else, or never ours): nothing is left for us to wait for.
    case notChild
}

struct PosixProcessControl: ProcessControl {
    func signalGroup(_ group: pid_t, _ signal: Int32) {
        guard group > 1 else { return }
        _ = killpg(group, signal)
    }

    func signalProcess(_ pid: pid_t, _ signal: Int32) {
        guard pid > 1 else { return }
        _ = kill(pid, signal)
    }

    func startTime(of pid: pid_t) -> UInt64? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info.pbi_start_tvsec &* 1_000_000 &+ info.pbi_start_tvusec
    }

    /// `waitpid` without blocking, retried when a signal interrupts it.
    func reap(_ pid: pid_t) -> ReapState {
        guard pid > 0 else { return .notChild }
        var status: Int32 = 0
        while true {
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid { return .reaped }
            if result == 0 { return .running }
            if errno == EINTR { continue }
            return .notChild
        }
    }

    func pause(_ seconds: Double) { usleep(UInt32(seconds * 1_000_000)) }
}

/// A shell as it was when the restart began: its pid, its foreground process group, and when each started, so that
/// a pid the system has handed to something else in the meantime is never signalled.
struct ShellTarget: Equatable, Sendable {
    var shellPid: pid_t
    var foregroundGroup: pid_t?
    var shellStart: UInt64?
    var foregroundStart: UInt64?
}

enum ShellEndOutcome: Equatable, Sendable {
    /// The shell left after the hang-up and was reaped.
    case reaped
    /// Someone else had already reaped it (SwiftTerm's own exit monitor).
    case alreadyGone
    /// It ignored the hang-up; SIGKILL ended it.
    case killed
    /// The pid now belongs to another process: nothing more was sent.
    case identityChanged
    /// Still alive after SIGKILL and the final wait (uninterruptible state).
    case stuck
}

/// What the session needs to end a shell for good.
protocol ShellTerminating: Sendable {
    /// Synchronous: captures the shell, sends SIGHUP to the foreground group (when it is not the shell's own) and then to the shell.
    func hangUp(shellPid: pid_t, foregroundGroup: pid_t?) -> ShellTarget
    /// Asynchronous, off the calling thread: waits for the shell, escalates to SIGKILL, reaps it.
    func reap(_ target: ShellTarget)
}

/// Ends a shell the way a closing terminal window does: SIGHUP to the foreground program and the shell, then
/// wait; a shell that ignores it gets SIGKILL after a grace period. Every wait runs on a background queue.
/// SwiftTerm's `terminate()` alone does not do this: it closes the PTY without the stop that raises SIGHUP,
/// sends SIGTERM (which an interactive zsh ignores) and cancels the exit monitor, so nothing ever reaps.
struct TerminalShellTerminator: ShellTerminating {
    var control: ProcessControl = PosixProcessControl()
    var pollInterval: Double = 0.02
    var graceTicks = 100  // about 2 s at the default interval
    var killTicks = 250  // about 5 s more after SIGKILL
    var queue = DispatchQueue(label: "mac-island.terminal.reaper", qos: .utility)
    /// Called on the background queue when the wait is over (tests wait on it).
    var completion: (@Sendable (ShellTarget, ShellEndOutcome) -> Void)?

    func hangUp(shellPid: pid_t, foregroundGroup: pid_t?) -> ShellTarget {
        let group = foregroundGroup.flatMap { $0 > 0 && $0 != shellPid ? $0 : nil }
        let target = ShellTarget(
            shellPid: shellPid, foregroundGroup: group,
            shellStart: control.startTime(of: shellPid), foregroundStart: group.flatMap { control.startTime(of: $0) })
        if let group { control.signalGroup(group, SIGHUP) }
        if target.shellStart != nil { control.signalProcess(shellPid, SIGHUP) }
        return target
    }

    func reap(_ target: ShellTarget) {
        let work = self
        queue.async {
            let outcome = work.settle(target)
            work.completion?(target, outcome)
        }
    }

    /// The whole wait, synchronous; `reap` runs it on the queue and tests call it directly with a fake.
    func settle(_ target: ShellTarget) -> ShellEndOutcome {
        for _ in 0..<graceTicks {
            if let done = poll(target) { return done }
            control.pause(pollInterval)
        }
        guard sameShell(target) else { return .identityChanged }
        if let group = target.foregroundGroup, sameGroupLeader(target, group) { control.signalGroup(group, SIGKILL) }
        if target.shellStart != nil, control.startTime(of: target.shellPid) == target.shellStart {
            control.signalProcess(target.shellPid, SIGKILL)
        }
        for _ in 0..<killTicks {
            if let done = poll(target) { return done == .reaped ? .killed : done }
            control.pause(pollInterval)
        }
        return .stuck
    }

    private func poll(_ target: ShellTarget) -> ShellEndOutcome? {
        if !sameShell(target) { return .identityChanged }
        switch control.reap(target.shellPid) {
        case .running: return nil
        case .reaped: return .reaped
        case .notChild: return .alreadyGone
        }
    }

    /// Alive and started when we captured it, or gone altogether (nil): never a different process under the same pid.
    private func sameShell(_ target: ShellTarget) -> Bool {
        guard let now = control.startTime(of: target.shellPid) else { return true }
        return now == target.shellStart
    }

    /// A group is signalled while its leader is the one captured or no longer exists (a group outlives its leader,
    /// and its id cannot be reused while a member remains); never when the pid is now another process.
    private func sameGroupLeader(_ target: ShellTarget, _ group: pid_t) -> Bool {
        guard let now = control.startTime(of: group) else { return true }
        return now == target.foregroundStart
    }
}
