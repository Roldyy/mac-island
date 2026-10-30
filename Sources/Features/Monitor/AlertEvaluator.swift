import Foundation

public enum AlertMetric: String, CaseIterable, Sendable {
    case cpu, memory
}

struct AlertRule: Equatable, Sendable {
    static let defaultClearMargin = 5.0

    /// Percent at or above which the signal counts as high.
    var threshold: Double
    /// How long it must stay high before the alert is raised.
    var sustained: TimeInterval
    /// Minimum time between two raises of the same metric.
    var cooldown: TimeInterval
    /// The alert clears once the value falls below `threshold - clearMargin`.
    var clearMargin: Double
}

enum AlertEvent: Equatable, Sendable {
    case raised(AlertMetric, Double)
    case cleared(AlertMetric)
}

/// Threshold + sustained duration + cool-down, with a clear margin so a value hovering at the
/// threshold does not flap. Pure: the clock is the `now` argument.
struct AlertEvaluator {
    private enum Phase {
        case idle
        case pending(since: Date)
        case active
    }
    private struct State {
        var phase: Phase = .idle
        var lastRaisedAt: Date?
    }

    private var states: [AlertMetric: State] = [:]

    func isActive(_ metric: AlertMetric) -> Bool {
        if case .active = states[metric]?.phase { return true }
        return false
    }

    mutating func reset() { states.removeAll() }

    mutating func evaluate(_ metric: AlertMetric, value: Double, rule: AlertRule, now: Date) -> AlertEvent? {
        var state = states[metric] ?? State()
        defer { states[metric] = state }

        switch state.phase {
        case .idle:
            guard value >= rule.threshold else { return nil }
            state.phase = .pending(since: now)
            return tryRaise(&state, metric, value, rule, since: now, now: now)
        case .pending(let since):
            guard value >= rule.threshold else {
                state.phase = .idle
                return nil
            }
            return tryRaise(&state, metric, value, rule, since: since, now: now)
        case .active:
            guard value < rule.threshold - rule.clearMargin else { return nil }
            state.phase = .idle
            return .cleared(metric)
        }
    }

    private func tryRaise(_ state: inout State, _ metric: AlertMetric, _ value: Double,
                          _ rule: AlertRule, since: Date, now: Date) -> AlertEvent? {
        guard now.timeIntervalSince(since) >= rule.sustained else { return nil }
        // Sustained, but still cooling down: stay pending; it raises once the cool-down is over
        // if the signal is still high, and is dropped if it falls back first.
        if let last = state.lastRaisedAt, now.timeIntervalSince(last) < rule.cooldown { return nil }
        state.phase = .active
        state.lastRaisedAt = now
        return .raised(metric, value)
    }
}
