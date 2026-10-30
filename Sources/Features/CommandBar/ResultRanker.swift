import Foundation

/// Habit data the ranker reads. Closures keep the ranker pure and testable.
struct HabitWeights {
    var weight: (String) -> Double
    var lastUsed: (String) -> Date?
    static let none = HabitWeights(weight: { _ in 0 }, lastUsed: { _ in nil })
}

/// Pure ranking: fuzzy match score, prefix boost, habit boost, recency, stable ordering.
enum ResultRanker {
    static let prefixBoost = 40.0
    static let wordPrefixBoost = 15.0
    static let keywordFactor = 0.6
    static let maxHabitBoost = 30.0
    static let maxRecencyBoost = 10.0
    static let recencyHalfLifeDays = 7.0

    /// Lower-cased, diacritic-free: "Écran" matches "ecran".
    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// 0...~100, nil when the query is not a subsequence of the text.
    /// Contiguous matches (70+) beat scattered ones (<60); word starts and exact matches add more.
    /// Greedy left-to-right alignment, not optimal: good enough for names, deterministic.
    static func fuzzyScore(query: String, text: String) -> Double? {
        let q = Array(normalize(query).filter { !$0.isWhitespace })
        let t = Array(normalize(text))
        guard !q.isEmpty, !t.isEmpty, q.count <= t.count else { return nil }
        let folded = String(t)
        let qs = String(q)
        if let range = folded.range(of: qs) {
            let start = folded.distance(from: folded.startIndex, to: range.lowerBound)
            let atWordStart = start == 0 || !t[start - 1].isLetter && !t[start - 1].isNumber
            var s = 70 + (atWordStart ? 15 : 0) + 15 * Double(q.count) / Double(t.count)
            if q.count == t.count { s = 100 }
            return s
        }
        var qi = 0, raw = 0.0, previous = -2
        for (i, c) in t.enumerated() where qi < q.count && c == q[qi] {
            let wordStart = i == 0 || !t[i - 1].isLetter && !t[i - 1].isNumber
            raw += 1 + (previous == i - 1 ? 2 : 0) + (wordStart ? 3 : 0)
            previous = i
            qi += 1
        }
        guard qi == q.count else { return nil }
        return min(59, 59 * raw / (6 * Double(q.count)))
    }

    static func score(_ r: BarResult, query: String, habits: HabitWeights, now: Date) -> Double? {
        if let fixed = r.fixedScore { return fixed }
        let title = fuzzyScore(query: query, text: r.title)
        let keyword = r.keywords.compactMap { fuzzyScore(query: query, text: $0) }.max().map { $0 * keywordFactor }
        guard let match = [title, keyword].compactMap({ $0 }).max() else { return nil }

        var total = match
        let q = normalize(query).trimmingCharacters(in: .whitespaces)
        let t = normalize(r.title)
        if t.hasPrefix(q) {
            total += prefixBoost
        } else if t.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(q) }) {
            total += wordPrefixBoost
        }
        total += habitBoost(r.id, habits: habits, now: now)
        return total
    }

    static func habitBoost(_ id: String, habits: HabitWeights, now: Date) -> Double {
        var boost = min(maxHabitBoost, 10 * log2(1 + max(0, habits.weight(id))))
        if let last = habits.lastUsed(id) {
            let days = max(0, now.timeIntervalSince(last)) / 86_400
            boost += maxRecencyBoost * pow(0.5, days / recencyHalfLifeDays)
        }
        return boost
    }

    static func rank(_ results: [BarResult], query: String, habits: HabitWeights = .none,
                     now: Date = Date(), limit: Int = 8) -> [BarResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        var scored: [(BarResult, Double)] = []
        if trimmed.isEmpty {
            // No query: only what the user actually uses, most used first.
            for r in results where r.fixedScore == nil {
                let w = habits.weight(r.id)
                if w > 0 { scored.append((r, habitBoost(r.id, habits: habits, now: now))) }
            }
        } else {
            for r in results {
                if let s = score(r, query: trimmed, habits: habits, now: now) { scored.append((r, s)) }
            }
        }
        scored.sort { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            let ta = normalize(a.0.title), tb = normalize(b.0.title)
            if ta != tb { return ta < tb }
            return a.0.id < b.0.id
        }
        // Pinned-last rows (web fallback) always survive the cap.
        let tail = scored.filter { ($0.0.fixedScore ?? 0) < 0 }
        let head = scored.filter { ($0.0.fixedScore ?? 0) >= 0 }.prefix(max(0, limit - tail.count))
        return (Array(head) + tail).map(\.0)
    }
}
