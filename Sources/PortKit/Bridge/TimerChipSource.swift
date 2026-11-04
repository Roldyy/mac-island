// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Status chips bridge (MIS_0102). Hand-written, never touched by import.sh.

import Combine
import Foundation
import ShellKit

/// Pure part of the "Minuteur" chip.
enum TimerChip {
    /// "4:32" with "Minuteur" (or the Pomodoro phase, "Chronomètre") under it, plus ", en pause" while paused; the
    /// ring is the elapsed fraction of a countdown. "Pause" while it runs, "Reprendre" while it waits. Nil when no
    /// session is active or the session is over (the end is an alert of the island, not a chip).
    static func reading(_ timer: TimerReading?, toggle: @escaping @MainActor () -> Void) -> StatusChipReading? {
        guard let timer, !timer.completed, timer.isRunning || timer.isPaused else { return nil }
        let word = TimerIndicator.phaseWord(timer)
        let action = StatusChipAction(
            id: "toggle", title: timer.isPaused ? "Reprendre" : "Pause",
            systemImage: timer.isPaused ? "play.fill" : "pause.fill", handler: toggle)
        return StatusChipReading(kind: .timer, primary: TimerIndicator.clockText(timer.seconds),
                                 secondary: timer.isPaused ? "\(word), en pause" : word,
                                 symbol: TimerIndicator.symbol(timer), progress: timer.progress, actions: [action])
    }
}

/// "Minuteur": the island's timer session (timer, Pomodoro, stopwatch) as a chip with a progress ring.
///
/// Event-driven: while started the chip observes `NotchTimerService.$session`, and a one-second wake-up runs only
/// while the clock runs (a paused or absent session needs none). The service itself is started by the Timer feature;
/// with it off there is no session and so no chip.
@MainActor
final class TimerChipSource: StatusChipBridgeSource {
    struct Hooks {
        /// Calls `deliver` when the session changed (after the change: the sink hops to the next main-queue turn).
        var changes: @MainActor (_ deliver: @escaping @MainActor () -> Void) -> AnyCancellable?
        var current: @MainActor () -> TimerReading?
        var toggle: @MainActor () -> Void
        var sleep: @Sendable (Duration) async throws -> Void

        @MainActor static let live = Hooks(
            changes: { deliver in
                NotchTimerService.shared.$session.receive(on: DispatchQueue.main)
                    .sink { _ in MainActor.assumeIsolated { deliver() } }
            },
            current: {
                let service = NotchTimerService.shared
                return TimerReading(session: service.session, now: service.now)
            },
            toggle: { NotchTimerService.shared.pauseOrResume() },
            sleep: StatusChipBridgeSource.sleeper(tolerance: .milliseconds(100)))
    }

    private let hooks: Hooks
    private var subscription: AnyCancellable?
    private var tick: Task<Void, Never>?

    init(hooks: Hooks? = nil) {
        self.hooks = hooks ?? .live
        super.init(kind: .timer)
    }

    override func begin() {
        subscription = hooks.changes { [weak self] in
            guard let self, self.isRunning else { return }
            self.refresh()
        }
        refresh()
    }

    override func end() {
        subscription = nil
        tick?.cancel()
        tick = nil
    }

    func refresh() {
        tick?.cancel()
        tick = nil
        let timer = hooks.current()
        let hooks = hooks
        publish(TimerChip.reading(timer, toggle: { hooks.toggle() }))
        guard isRunning, let timer, timer.isRunning, !timer.completed else { return }
        let sleep = hooks.sleep
        tick = Task { [weak self] in
            do { try await sleep(.seconds(1)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
