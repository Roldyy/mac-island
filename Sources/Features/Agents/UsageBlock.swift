import Foundation

/// The 5-hour billing window Claude Code subscriptions count in.
struct UsageBlock: Equatable, Sendable {
    var start: Date
    var end: Date
    var lastActivity: Date
    var tokens: Int
    var cost: Double
    var estimated: Bool

    func remaining(at now: Date) -> TimeInterval { max(0, end.timeIntervalSince(now)) }
}

/// ccusage rule: a block starts at the first message after a gap of more than 5 h (or once the previous
/// block's 5 h are over), at that message's time floored to the hour (UTC, so half-hour zones agree with
/// ccusage). Pure.
enum UsageBlocks {
    static let length: TimeInterval = 5 * 3600

    static func floorToHour(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
    }

    /// The block `now` falls in, or nil when the last block is over (idle for 5 h, or past its end).
    static func active(_ records: [UsageRecord], now: Date) -> UsageBlock? {
        var current: UsageBlock?
        for record in records.filter({ $0.timestamp <= now }).sorted(by: { $0.timestamp < $1.timestamp }) {
            if let block = current,
               record.timestamp < block.end,
               record.timestamp.timeIntervalSince(block.lastActivity) <= length {
                current = add(record, to: block)
            } else {
                let start = floorToHour(record.timestamp)
                current = add(record, to: UsageBlock(start: start, end: start.addingTimeInterval(length),
                                                     lastActivity: record.timestamp, tokens: 0, cost: 0,
                                                     estimated: false))
            }
        }
        guard let block = current, now < block.end, now.timeIntervalSince(block.lastActivity) < length else { return nil }
        return block
    }

    private static func add(_ record: UsageRecord, to block: UsageBlock) -> UsageBlock {
        let price = PriceTable.price(for: record.model)
        var next = block
        next.lastActivity = max(block.lastActivity, record.timestamp)
        next.tokens += record.totalTokens
        next.cost += price.perMillion.cost(of: record)
        if price.estimated { next.estimated = true }
        return next
    }
}
