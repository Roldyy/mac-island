// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Status chips bridge (MIS_0102). Hand-written, never touched by import.sh.

import Foundation
import ShellKit

/// The start/stop rules of ShellKit's `StatusChipSource` contract, shared by the five bridge chips.
///
/// ShellKit's own `StatusChipPolledSource` is internal to that module, so the bridge keeps its own copy of the same
/// plumbing: the reading, the change callback, idempotent `start()` / `stop()`, and a `publish` that assigns only a
/// changed reading while running (a late sample after `stop()` is dropped). A subclass starts its poller or listener
/// in `begin()` and cancels every one of them in `end()`: nothing runs outside that window.
@MainActor
class StatusChipBridgeSource: StatusChipSource {
    let kind: StatusChipKind
    private(set) var reading: StatusChipReading?
    var onChange: (@MainActor () -> Void)?
    private(set) var isRunning = false

    init(kind: StatusChipKind) { self.kind = kind }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        begin()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        end()
        reading = nil
    }

    /// Subclass hook: start the poller and any listener.
    func begin() {}
    /// Subclass hook: cancel the poller and every listener.
    func end() {}

    func publish(_ new: StatusChipReading?) {
        guard isRunning, new != reading else { return }
        reading = new
        onChange?()
    }

    /// A poller `sleep` with leeway, so the system can coalesce the wake-ups.
    nonisolated static func sleeper(tolerance: Duration) -> @Sendable (Duration) async throws -> Void {
        { try await Task.sleep(for: $0, tolerance: tolerance) }
    }
}
