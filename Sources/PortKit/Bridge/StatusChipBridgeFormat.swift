// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Status chips bridge (MIS_0102). Hand-written, never touched by import.sh.

import Foundation

/// French text of the bridge chips, with no system call: numbers in, words out.
enum StatusChipBridgeFormat {
    /// The text cut to `limit` characters, an ellipsis replacing the tail; surrounding blanks go.
    static func truncated(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 1, trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// "45 min", "3 h 20 min", "2 h".
    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0 min" }
        let minutes = Int((seconds / 60).rounded())
        let (hours, rest) = (minutes / 60, minutes % 60)
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    /// Whole minutes left, rounded up: the clock a countdown shows ("dans 12 min" for 11 min 20 s).
    static func minutesLeft(until start: Date, now: Date) -> Int {
        let remaining = start.timeIntervalSince(now)
        guard remaining.isFinite, remaining > 0 else { return 0 }
        return Int((remaining / 60).rounded(.up))
    }

    /// "dans 12 min", "dans 1 h 05", "dans 2 h", "maintenant".
    static func countdown(until start: Date, now: Date) -> String {
        let minutes = minutesLeft(until: start, now: now)
        guard minutes > 0 else { return "maintenant" }
        if minutes < 60 { return "dans \(minutes) min" }
        let (hours, rest) = (minutes / 60, minutes % 60)
        return rest == 0 ? "dans \(hours) h" : "dans \(hours) h \(String(format: "%02d", rest))"
    }

    /// "1 cycle", "312 cycles".
    static func cycles(_ count: Int) -> String { count > 1 ? "\(count) cycles" : "\(max(count, 0)) cycle" }

    /// "+1 autre", "+2 autres".
    static func others(_ count: Int) -> String { count > 1 ? "+\(count) autres" : "+\(count) autre" }
}
