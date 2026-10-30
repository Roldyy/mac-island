import AppKit
import Darwin

protocol RunningAppScanning {
    @MainActor func snapshot() -> [AppSnapshot]
}

protocol AppTerminating {
    /// Polite `terminate()` only: the app may show a save prompt. Never a forced quit.
    @MainActor func terminate(pid: Int32) -> Bool
}

/// Parent pid through `proc_pidinfo`; nil when the process is gone or unreadable.
func parentPID(of pid: Int32) -> Int32? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
    return Int32(bitPattern: info.pbi_ppid)
}

struct RunningAppScanner: RunningAppScanning {
    @MainActor func snapshot() -> [AppSnapshot] {
        let counts = WindowCounter.currentCounts()
        let running = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        var byPID: [Int32: String] = [:]
        for app in running where app.activationPolicy == .regular {
            if let bundle = app.bundleIdentifier { byPID[app.processIdentifier] = bundle }
        }
        let audio = AudioActivity.attribute(
            playing: AudioActivity.playingProcesses(), apps: byPID,
            knownPIDs: Set(running.map(\.processIdentifier)), parentOf: parentPID(of:))
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return running.map { app in
            let pid = app.processIdentifier
            return AppSnapshot(
                pid: pid, bundleID: app.bundleIdentifier,
                name: app.localizedName ?? app.bundleIdentifier ?? "?",
                isRegular: app.activationPolicy == .regular,
                isFrontmost: pid == frontPID || app.isActive,
                // A process playing sound that no app owns (a system web-engine service) could be
                // any app's: keep them all this scan rather than quit the one that is playing.
                isPlayingAudio: audio.appPIDs.contains(pid) || audio.hasUnattributed,
                windowCount: counts[pid] ?? 0,
                isHidden: app.isHidden)
        }
    }
}

struct WorkspaceTerminator: AppTerminating {
    @MainActor func terminate(pid: Int32) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.terminate() ?? false
    }
}
