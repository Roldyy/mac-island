import Foundation

/// One meter of the "Limites" card.
struct LimitRow: Equatable, Identifiable, Sendable {
    enum Kind: String, Sendable { case session, weekly }

    var kind: Kind
    /// Whole percent of the window used. nil = unknown: the meter then shows no fill and no figure.
    var usedPercent: Int?
    /// Share of the window already elapsed (0...1), when the window's bounds are known.
    var elapsed: Double?
    var renewal: Date?
    /// Tokens of the window as counted from the Claude Code logs (estimate only).
    var tokens: Int?

    var id: String { kind.rawValue }
    var title: String { AgentsStrings.text(kind == .session ? "session" : "weekly") }

    /// The fill of the meter: what is left or what is used.
    func fill(_ display: AgentsLimitDisplay) -> Double? {
        usedPercent.map { display == .used ? Double($0) / 100 : Double(100 - $0) / 100 }
    }

    /// Pace marker: where the fill would sit if usage were perfectly even over the window.
    func paceMarker(_ display: AgentsLimitDisplay) -> Double? {
        elapsed.map { display == .used ? $0 : 1 - $0 }
    }

    func valueText(_ display: AgentsLimitDisplay) -> String? {
        guard let fill = fill(display) else { return nil }
        return AgentsStrings.format(display == .used ? "usedFormat" : "leftFormat", UsageFormat.percent(fill))
    }
}

/// Where the limits came from. Never a guess: `none` shows the waiting line.
enum LimitsSource: Equatable, Sendable { case planFile, estimatedFromLogs, none }

/// Everything the "Limites" card and the closed island need. Pure: built from the file sample, the
/// 5-hour block counted in the logs and the clock. No percentage is ever derived from a token budget.
struct LimitsState: Equatable, Sendable {
    var rows: [LimitRow] = []
    var source = LimitsSource.none
    var updated: Date?
    var isStale = false
    var extraUsage: Int?

    /// Share of a window elapsed at `now`, nil when the bounds do not make a window.
    static func elapsedFraction(now: Date, start: Date, end: Date) -> Double? {
        let length = end.timeIntervalSince(start)
        guard length > 0 else { return nil }
        return min(1, max(0, now.timeIntervalSince(start) / length))
    }

    static func resolve(sample: PlanLimitSample?, block: UsageBlock?, weekTokens: Int, now: Date) -> LimitsState {
        func sessionBounds() -> (elapsed: Double?, renewal: Date?) {
            guard let block, block.end > now else { return (nil, nil) }
            return (elapsedFraction(now: now, start: block.start, end: block.end), block.end)
        }
        if let sample, sample.hasAnyValue {
            var state = LimitsState(source: .planFile, updated: sample.date, isStale: sample.isStale(at: now),
                                    extraUsage: sample.extraUsage)
            if let fiveHour = sample.fiveHour {
                let bounds = sessionBounds()
                state.rows.append(LimitRow(kind: .session, usedPercent: fiveHour, elapsed: bounds.elapsed,
                                           renewal: bounds.renewal))
            }
            if let sevenDay = sample.sevenDay { state.rows.append(LimitRow(kind: .weekly, usedPercent: sevenDay)) }
            return state
        }
        guard let block, block.end > now else { return LimitsState() }
        let bounds = sessionBounds()
        return LimitsState(rows: [
            LimitRow(kind: .session, usedPercent: nil, elapsed: bounds.elapsed, renewal: bounds.renewal, tokens: block.tokens),
            LimitRow(kind: .weekly, usedPercent: nil, tokens: weekTokens),
        ], source: .estimatedFromLogs)
    }

    /// The limit the closed island shows. nil when that limit has no percentage.
    func focused(_ focus: AgentsLimitFocus) -> LimitRow? {
        let known = rows.filter { $0.usedPercent != nil }
        switch focus {
        case .session: return known.first { $0.kind == .session }
        case .weekly: return known.first { $0.kind == .weekly }
        case .mostUsed:
            return known.reduce(nil as LimitRow?) { best, row in
                guard let best else { return row }
                return (row.usedPercent ?? 0) > (best.usedPercent ?? 0) ? row : best
            }
        }
    }
}
