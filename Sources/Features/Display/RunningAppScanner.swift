import AppKit

protocol RunningAppScanning {
    @MainActor func snapshot() -> [AppSnapshot]
}

protocol AppTerminating {
    /// Polite `terminate()` only: the app may show a save prompt. Never a forced quit.
    @MainActor func terminate(pid: Int32) -> Bool
}

struct RunningAppScanner: RunningAppScanning {
    @MainActor func snapshot() -> [AppSnapshot] {
        let counts = WindowCounter.currentCounts()
        let audio = AudioActivity.playingPIDs()
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard !app.isTerminated else { return nil }
            let pid = app.processIdentifier
            return AppSnapshot(
                pid: pid, bundleID: app.bundleIdentifier,
                name: app.localizedName ?? app.bundleIdentifier ?? "?",
                isRegular: app.activationPolicy == .regular,
                isFrontmost: pid == frontPID || app.isActive,
                isPlayingAudio: audio.contains(pid),
                windowCount: counts[pid] ?? 0)
        }
    }
}

struct WorkspaceTerminator: AppTerminating {
    @MainActor func terminate(pid: Int32) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.terminate() ?? false
    }
}
