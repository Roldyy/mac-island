import Darwin
import Foundation

/// What applying a colour profile must do to the running terminal.
enum TerminalRestartDecision: Equatable {
    /// No shell is running: the profile is simply read when the terminal starts.
    case colorsOnNextStart
    /// Only the shell is in the foreground: restart it at once.
    case restart
    /// Another program owns the terminal: ask before ending it, never kill it silently.
    case confirm(process: String)

    /// `foregroundGroup` is the terminal's foreground process group; the shell leads its own group, so a
    /// different group means a command is running in front of it (a background job does not count).
    static func decide(hasSession: Bool, shellPid: pid_t, foregroundGroup: pid_t?, foregroundName: String?) -> Self {
        guard hasSession else { return .colorsOnNextStart }
        guard let group = foregroundGroup, group > 0, group != shellPid else { return .restart }
        let name = TerminalColorProfile.sanitizedName(foregroundName ?? "", fallback: "un programme")
        return .confirm(process: name)
    }
}

/// What the terminal session offers the Settings model: a decision, then the restart itself.
@MainActor
protocol TerminalRestarting: AnyObject {
    func restartDecision() -> TerminalRestartDecision
    func restartWithActiveProfile()
}

/// Reads about a child process; nothing is kept.
enum TerminalProcessInfo {
    /// The shell's current directory, only when it is an existing directory; otherwise the home folder.
    static func usableDirectory(of pid: pid_t) -> String {
        guard let path = currentDirectory(of: pid) else { return NSHomeDirectory() }
        return usableDirectory(path)
    }

    static func usableDirectory(_ path: String) -> String {
        var isDirectory: ObjCBool = false
        guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue
        else { return NSHomeDirectory() }
        return path
    }

    static func currentDirectory(of pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        return path.isEmpty ? nil : path
    }

    /// The foreground process group of the pseudo-terminal whose primary side is `masterFd`.
    static func foregroundGroup(masterFd: Int32) -> pid_t? {
        guard masterFd >= 0 else { return nil }
        let group = tcgetpgrp(masterFd)
        return group > 0 ? group : nil
    }

    static func processName(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}
