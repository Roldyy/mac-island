import Foundation
import IslandUI

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
    /// The reading cannot be told yet (the log records that decide it are still being read): the page draws
    /// a neutral placeholder for this meter, never a number that may turn out to belong to another window.
    var isPending = false

    /// Settled, but nothing to show: the last plan reading predates the window and no 5 h block is open.
    var isIdle: Bool { !isPending && usedPercent == nil && tokens == nil }

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

    /// Whole percent still available; nil when unknown.
    var leftPercent: Int? { usedPercent.map { 100 - $0 } }

    var level: LimitLevel? { leftPercent.map(LimitLevel.init(leftPercent:)) }

    func valueText(_ display: AgentsLimitDisplay) -> String? {
        guard let fill = fill(display) else { return nil }
        return AgentsStrings.format(display == .used ? "usedFormat" : "leftFormat", UsageFormat.percent(fill))
    }
}

/// How much of a limit is left, as a word and a symbol: color is never the only signal.
enum LimitLevel: Equatable, Sendable {
    case comfortable, watch, critical

    /// More than 50 % left is comfortable, 20 to 50 % to watch, under 20 % critical.
    init(leftPercent: Int) {
        self = leftPercent > 50 ? .comfortable : leftPercent >= 20 ? .watch : .critical
    }

    var status: IslandStatus {
        switch self {
        case .comfortable: .success
        case .watch: .warning
        case .critical: .danger
        }
    }

    var label: String {
        switch self {
        case .comfortable: AgentsStrings.levelComfortable
        case .watch: AgentsStrings.levelWatch
        case .critical: AgentsStrings.levelCritical
        }
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
    /// A row of a plan-file state that fell back to the log estimate (its reading predates the window).
    var hasEstimatedRow = false

    /// Share of a window elapsed at `now`, nil when the bounds do not make a window.
    static func elapsedFraction(now: Date, start: Date, end: Date) -> Double? {
        let length = end.timeIntervalSince(start)
        guard length > 0 else { return nil }
        return min(1, max(0, now.timeIntervalSince(start) / length))
    }

    /// - Parameters:
    ///   - blockKnown: the log records have been read far enough to say which 5 h block is open (or that none
    ///     is). While false, a session reading that may belong to an earlier window stays pending.
    ///   - weekComplete: the week's tokens are final (only the log estimate uses them).
    static func resolve(sample: PlanLimitSample?, block: UsageBlock?, blockKnown: Bool = true, weekTokens: Int,
                        weekComplete: Bool = true, now: Date) -> LimitsState {
        let open = block.flatMap { $0.end > now ? $0 : nil }
        func sessionBounds() -> (elapsed: Double?, renewal: Date?) {
            guard let open else { return (nil, nil) }
            return (elapsedFraction(now: now, start: open.start, end: open.end), open.end)
        }
        if let sample, sample.hasAnyValue {
            var state = LimitsState(source: .planFile, updated: sample.date, isStale: sample.isStale(at: now),
                                    extraUsage: sample.extraUsage)
            if let fiveHour = sample.fiveHour {
                let bounds = sessionBounds()
                // A reading older than the 5 h window, or taken before the open block began, describes a
                // previous window: it is never shown as the current session.
                let outdated = now.timeIntervalSince(sample.date) > UsageBlocks.length
                    || open.map { sample.date < $0.start } == true
                if blockKnown {
                    if outdated, let open {
                        state.rows.append(LimitRow(kind: .session, usedPercent: nil, elapsed: bounds.elapsed,
                                                   renewal: bounds.renewal, tokens: open.tokens))
                        state.hasEstimatedRow = true
                    } else if outdated {
                        state.rows.append(LimitRow(kind: .session, usedPercent: nil))
                    } else {
                        state.rows.append(LimitRow(kind: .session, usedPercent: fiveHour, elapsed: bounds.elapsed,
                                                   renewal: bounds.renewal))
                    }
                } else if outdated {
                    state.rows.append(LimitRow(kind: .session, usedPercent: nil, isPending: true))
                } else {
                    // Within 5 h and nothing in the (partial) logs contradicts it: it can still be the current one.
                    state.rows.append(LimitRow(kind: .session, usedPercent: fiveHour, elapsed: bounds.elapsed,
                                               renewal: bounds.renewal))
                }
            }
            if let sevenDay = sample.sevenDay { state.rows.append(LimitRow(kind: .weekly, usedPercent: sevenDay)) }
            return state
        }
        guard blockKnown else {
            return LimitsState(rows: [LimitRow(kind: .session, usedPercent: nil, isPending: true),
                                      LimitRow(kind: .weekly, usedPercent: nil, isPending: true)])
        }
        guard let open else { return LimitsState() }
        let bounds = sessionBounds()
        return LimitsState(rows: [
            LimitRow(kind: .session, usedPercent: nil, elapsed: bounds.elapsed, renewal: bounds.renewal, tokens: open.tokens),
            LimitRow(kind: .weekly, usedPercent: nil, tokens: weekComplete ? weekTokens : nil, isPending: !weekComplete),
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
