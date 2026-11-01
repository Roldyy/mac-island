// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Lane W3D (auto-quit and Spaces). The lane owns this file.

import Foundation

/// The only place in the port that restarts the Dock (patch 0851 routes `SpacesOrderSystem.live.restartDock`
/// here). Two rules on top of upstream's own "only when the preference really changed" logic:
///
/// - a minimum interval between two restarts, so a quick on/off toggle, a crash loop or a retry can never make
///   the Dock flap: a restart asked inside the interval is REFUSED (the hold keeps its journal, which is how
///   upstream models "a restart is still owed") and ONE retry is scheduled for when the interval is over;
/// - a restart that failed does not count as a restart, so the next ask is not held back by it.
///
/// Thread-safe: the hold calls it from its serial queue, tests from the main thread.
final class SpacesDockRestartGuard: @unchecked Sendable {
    static let minimumInterval: TimeInterval = 15
    static let shared = SpacesDockRestartGuard()

    private let lock = NSLock()
    private let interval: TimeInterval
    private let now: () -> Date
    private let run: () -> Bool
    private let scheduleRetry: (TimeInterval) -> Void
    private var lastRestart: Date?
    private var retryScheduled = false

    /// `run` is the one `killall Dock`. A Dock that is terminated counts as an unexpected exit, so the system
    /// starts it again at once; a clean quit would leave it closed.
    init(interval: TimeInterval = SpacesDockRestartGuard.minimumInterval,
         now: @escaping () -> Date = Date.init,
         run: @escaping () -> Bool = { Shell.run("/usr/bin/killall", ["Dock"]).status == 0 },
         scheduleRetry: @escaping (TimeInterval) -> Void = { delay in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                 SpacesOrderHold.shared.syncWithPreferences()
             }
         }) {
        self.interval = interval
        self.now = now
        self.run = run
        self.scheduleRetry = scheduleRetry
    }

    /// True when the Dock was restarted. False when the interval has not passed (nothing ran) or the command failed.
    func restart() -> Bool {
        lock.lock()
        let current = now()
        if let last = lastRestart, current.timeIntervalSince(last) < interval {
            let wait = interval - current.timeIntervalSince(last)
            let schedule = !retryScheduled
            retryScheduled = true
            lock.unlock()
            if schedule { scheduleRetry(wait + 0.5) }
            return false
        }
        retryScheduled = false
        // The lock stays held while the command runs (bounded: `Shell.run` times out), so two callers can never
        // both pass the interval check and restart the Dock twice.
        defer { lock.unlock() }
        guard run() else { return false }
        lastRestart = now()
        return true
    }
}
