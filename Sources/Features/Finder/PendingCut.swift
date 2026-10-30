import Foundation

/// The items marked by Cmd+X. Pure value; the clock and the pasteboard change count are passed in, never read.
struct PendingCut: Equatable {
    static let lifetime: TimeInterval = 120

    private(set) var items: [URL] = []
    private(set) var markedAt: Date?
    private(set) var pasteboardChangeCount: Int?

    var expiresAt: Date? {
        guard let markedAt, !items.isEmpty else { return nil }
        return markedAt.addingTimeInterval(Self.lifetime)
    }

    mutating func mark(_ new: [URL], now: Date, pasteboardChangeCount: Int? = nil) {
        var seen = Set<String>()
        items = new.filter { seen.insert($0.path).inserted }
        markedAt = items.isEmpty ? nil : now
        self.pasteboardChangeCount = items.isEmpty ? nil : pasteboardChangeCount
    }

    /// Keeps only `keep` (a failed move: the sources that still exist). Neither the first
    /// `markedAt` nor the pasteboard count change, so a retry never earns a fresh 120 s.
    mutating func retain(_ keep: [URL]) {
        let kept = Set(keep.map(\.path))
        items = items.filter { kept.contains($0.path) }
        if items.isEmpty { cancel() }
    }

    mutating func cancel() {
        items = []
        markedAt = nil
        pasteboardChangeCount = nil
    }

    func isActive(now: Date, pasteboardChangeCount current: Int? = nil) -> Bool {
        guard let at = markedAt, !items.isEmpty else { return false }
        // Something else was copied since the cut: the pasteboard now holds the user's newer intent.
        if let mine = pasteboardChangeCount, let current, mine != current { return false }
        return now.timeIntervalSince(at) <= Self.lifetime
    }

    func activeItems(now: Date, pasteboardChangeCount current: Int? = nil) -> [URL] {
        isActive(now: now, pasteboardChangeCount: current) ? items : []
    }
    func count(now: Date, pasteboardChangeCount current: Int? = nil) -> Int {
        activeItems(now: now, pasteboardChangeCount: current).count
    }
}
