import Darwin
import Foundation

/// Answers "is this pid alive, and since when". The start time defends against pid reuse.
public protocol ProcessLivenessProbe: Sendable {
    /// Start time of the process, nil when it does not exist (or cannot be read).
    func startTime(ofPID pid: Int32) -> Date?
}

/// Real probe: `proc_pidinfo`, no subprocess, no private API.
public struct SystemProcessProbe: ProcessLivenessProbe {
    public init() {}

    public func startTime(ofPID pid: Int32) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_start_tvsec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec))
    }
}

enum ProcStart {
    /// Allowed gap between the `procStart` text (second precision, local time) and the probe.
    static let tolerance: TimeInterval = 2

    /// Parses the `ps lstart` style text Claude Code writes ("Tue Oct 27 10:45:47 2026").
    static func parse(_ raw: String) -> Date? {
        guard raw.utf8.count <= 40 else { return nil }
        let normalized = raw.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return f.date(from: normalized)
    }

    static func matches(_ raw: String, actual: Date) -> Bool {
        guard let claimed = parse(raw) else { return false }
        return abs(claimed.timeIntervalSince(actual)) <= tolerance
    }
}
