// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Status chips bridge (MIS_0102). Hand-written, never touched by import.sh.

import Foundation

/// The processor temperature for the "Charge" chip, with a reference on `SystemMonitor` held only while that chip
/// asks for it.
///
/// ShellKit's Load chip calls the temperature provider once per 2 s tick and gives it no start or stop hook. So the
/// first call takes one `panelDidAppear()` reference (without it the monitor is idle on the Home tab and the SMC is
/// never read), every call re-arms a single idle task, and when no call came for `idleTimeout` (the chip stopped,
/// the island closed) that task gives the reference back with `panelDidDisappear()`. One acquire, one release, no
/// timer outside that window. The first call answers nil: the monitor has not read the sensor yet.
@MainActor
final class CPUTemperatureLease {
    struct Hooks {
        var acquire: @MainActor () -> Void
        var release: @MainActor () -> Void
        /// The latest temperature, nil when unknown or too old to trust.
        var read: @MainActor () -> Double?
        var sleep: @Sendable (Duration) async throws -> Void

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
            },
            sleep: { try await Task.sleep(for: $0, tolerance: .seconds(1)) })
    }

    /// Four 2 s ticks of silence: the Load chip is no longer polling.
    nonisolated static let idleTimeout: Duration = .seconds(8)

    @MainActor static let shared = CPUTemperatureLease(hooks: .live)

    private let hooks: Hooks
    private let idleTimeout: Duration
    private var idle: Task<Void, Never>?
    private(set) var isHeld = false

    init(hooks: Hooks, idleTimeout: Duration = CPUTemperatureLease.idleTimeout) {
        self.hooks = hooks
        self.idleTimeout = idleTimeout
    }

    func temperature() -> Double? {
        if !isHeld {
            isHeld = true
            hooks.acquire()
        }
        idle?.cancel()
        let (sleep, timeout) = (hooks.sleep, idleTimeout)
        idle = Task { [weak self] in
            do { try await sleep(timeout) } catch { return }
            guard !Task.isCancelled else { return }
            self?.expire()
        }
        return hooks.read()
    }

    /// Gives the reference back (idempotent).
    func expire() {
        idle?.cancel()
        idle = nil
        guard isHeld else { return }
        isHeld = false
        hooks.release()
    }
}
