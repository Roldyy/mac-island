import Foundation

/// Pure description of one keep-awake session: when it started and how long it may last.
struct SessionPlan: Equatable {
    let start: Date
    /// Seconds. nil = no limit.
    let duration: TimeInterval?

    init(start: Date, duration: TimeInterval?) {
        self.start = start
        self.duration = duration
    }

    /// Minutes as stored in `defaultDurationMinutes`; 0 or less means no limit.
    init(start: Date, minutes: Int) {
        self.init(start: start, duration: minutes > 0 ? TimeInterval(minutes) * 60 : nil)
    }

    var expiry: Date? { duration.map { start.addingTimeInterval($0) } }

    func remaining(at now: Date) -> TimeInterval? {
        guard let expiry else { return nil }
        return max(0, expiry.timeIntervalSince(now))
    }

    func isExpired(at now: Date) -> Bool {
        guard let expiry else { return false }
        return now >= expiry
    }

    /// "m:ss" under an hour, "h:mm:ss" above; rounds up so 0.4 s shows 0:01.
    static func format(remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
