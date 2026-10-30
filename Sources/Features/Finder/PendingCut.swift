import Foundation

/// The items marked by Cmd+X. Pure value; the clock is passed in, never read.
struct PendingCut: Equatable {
    static let lifetime: TimeInterval = 120

    private(set) var items: [URL] = []
    private(set) var markedAt: Date?

    mutating func mark(_ new: [URL], now: Date) {
        var seen = Set<String>()
        items = new.filter { seen.insert($0.path).inserted }
        markedAt = items.isEmpty ? nil : now
    }

    mutating func cancel() {
        items = []
        markedAt = nil
    }

    func isActive(now: Date) -> Bool {
        guard let at = markedAt, !items.isEmpty else { return false }
        return now.timeIntervalSince(at) <= Self.lifetime
    }

    func activeItems(now: Date) -> [URL] { isActive(now: now) ? items : [] }
    func count(now: Date) -> Int { activeItems(now: now).count }
}
