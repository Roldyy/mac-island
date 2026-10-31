import Foundation

/// How much of the log folder a snapshot already accounts for. Files are read newest first and a log never
/// holds a record newer than its own modification date, so a period is complete as soon as every file
/// modified inside it has been read. Pure.
struct UsageCoverage: Equatable, Sendable {
    /// Newest modification date among files with no data yet. nil = nothing is missing.
    var missingNewest: Date?

    static let complete = UsageCoverage(missingNewest: nil)
    /// Nothing read yet.
    static let unread = UsageCoverage(missingNewest: .distantFuture)

    var isComplete: Bool { missingNewest == nil }

    func covers(_ period: UsagePeriod, now: Date, calendar: Calendar) -> Bool {
        guard let missingNewest else { return true }
        return period.interval(now: now, calendar: calendar).start > missingNewest
    }
}
