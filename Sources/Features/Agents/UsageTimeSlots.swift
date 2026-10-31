import Foundation

/// Start of day and start of hour for a timestamp, memoised per 15-minute slot. A calendar lookup costs
/// microseconds and the snapshot asks for every record; a slot never straddles a local midnight or hour,
/// because every real UTC offset is a multiple of 15 minutes, so one lookup serves the whole slot.
struct UsageTimeSlots {
    static let slotLength: TimeInterval = 900

    private let calendar: Calendar
    private var days: [Int: Date] = [:]
    private var hours: [Int: Date?] = [:]

    init(calendar: Calendar) { self.calendar = calendar }

    private static func slot(_ date: Date) -> Int { Int((date.timeIntervalSince1970 / slotLength).rounded(.down)) }

    mutating func day(of date: Date) -> Date {
        let key = Self.slot(date)
        if let hit = days[key] { return hit }
        let start = calendar.startOfDay(for: date)
        days[key] = start
        return start
    }

    mutating func hour(of date: Date) -> Date? {
        let key = Self.slot(date)
        if let hit = hours[key] { return hit }
        let start = calendar.dateInterval(of: .hour, for: date)?.start
        hours[key] = .some(start)
        return start
    }
}
