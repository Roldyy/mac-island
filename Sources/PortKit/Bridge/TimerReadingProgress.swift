// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Status chips bridge (MIS_0102). Hand-written, never touched by import.sh.

import Foundation

extension TimerReading {
    /// How much of a countdown has elapsed, 0...1 (a ring that fills up). Nil for a stopwatch and for a countdown
    /// with no length, which have no end to fill towards.
    var progress: Double? {
        guard mode != .stopwatch, duration > 0 else { return nil }
        return min(1, max(0, 1 - seconds / duration))
    }
}
