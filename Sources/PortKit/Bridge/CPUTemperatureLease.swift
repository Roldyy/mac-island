// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Status chips bridge (MIS_0102). Hand-written, never touched by import.sh.

import Foundation

/// The processor temperature for the "Charge" chip, with a reference on `SystemMonitor` held only while that chip
/// runs.
///
/// The first `temperature()` call of a run takes one `panelDidAppear()` reference (without it the monitor is idle on
/// the Home tab and the SMC is never read); `release()` gives it back, exactly once. ShellKit's Load chip calls
/// `release()` from `end()` (`ShellContext.statusTemperatureStop`) and calls `temperature()` only while it runs, so
/// nothing stays held after the island closes: no timer, no task. The first call answers nil: the monitor has not
/// read the sensor yet.
@MainActor
final class CPUTemperatureLease {
    struct Hooks {
        var acquire: @MainActor () -> Void
        var release: @MainActor () -> Void
        /// The latest temperature, nil when unknown or too old to trust.
        var read: @MainActor () -> Double?

        /// A value the monitor carried over from an earlier run is older than this (system uptime, seconds).
        static let maxAge: TimeInterval = 30

        /// `value` when it was really read recently, nil otherwise (pure).
        static func fresh(_ value: Double?, readAt: TimeInterval?, now: TimeInterval) -> Double? {
            guard let value, value.isFinite, let readAt, now - readAt <= maxAge else { return nil }
            return value
        }

        @MainActor static let live = Hooks(
            acquire: { SystemMonitor.shared.panelDidAppear() },
            release: { SystemMonitor.shared.panelDidDisappear() },
            read: {
                let snapshot = SystemMonitor.shared.snapshot
                return fresh(snapshot.cpuTemperature, readAt: snapshot.cpuTemperatureReadAt,
                             now: ProcessInfo.processInfo.systemUptime)
            })
    }

    @MainActor static let shared = CPUTemperatureLease(hooks: .live)

    private let hooks: Hooks
    private(set) var isHeld = false

    init(hooks: Hooks) { self.hooks = hooks }

    func temperature() -> Double? {
        if !isHeld {
            isHeld = true
            hooks.acquire()
        }
        return hooks.read()
    }

    /// Gives the reference back (idempotent).
    func release() {
        guard isHeld else { return }
        isHeld = false
        hooks.release()
    }
}
