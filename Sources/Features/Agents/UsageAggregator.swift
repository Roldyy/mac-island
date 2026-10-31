import Foundation

struct DayUsage: Equatable, Identifiable, Sendable {
    var day: Date
    var tokens: Int
    var cost: Double
    var id: Date { day }
}

struct ModelUsage: Equatable, Identifiable, Sendable {
    var model: String
    var tokens: Int
    var cost: Double
    var estimated: Bool
    var id: String { model }
}

struct ProjectUsage: Equatable, Identifiable, Sendable {
    var name: String
    var tokens: Int
    var cost: Double
    var estimated: Bool
    var id: String { name }
}

struct UsageSummary: Equatable, Sendable {
    var totalTokens = 0
    var totalCost = 0.0
    var costIsEstimated = false
    var perDay: [DayUsage] = []
    /// Filled for `.today` only: the day's bars are hours.
    var perHour: [DayUsage] = []
    var perModel: [ModelUsage] = []
    var perProject: [ProjectUsage] = []
    var agentTokens: [UsageAgent: Int] = [:]
}

/// Pure: every window is computed from the injected clock and calendar.
enum UsageAggregator {
    static let noProject = "Sans dossier"

    static func monthStart(containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func summarize(_ records: [UsageRecord], now: Date, calendar: Calendar,
                          period: UsagePeriod = .month) -> UsageSummary {
        let window = period.interval(now: now, calendar: calendar)
        var days: [Date: (tokens: Int, cost: Double)] = [:]
        var hours: [Date: (tokens: Int, cost: Double)] = [:]
        var models: [String: (tokens: Int, cost: Double, estimated: Bool)] = [:]
        var projects: [String: (tokens: Int, cost: Double, estimated: Bool)] = [:]
        var summary = UsageSummary()
        for record in records where record.timestamp >= window.start && record.timestamp < window.end {
            let price = PriceTable.price(for: record.model)
            let cost = price.perMillion.cost(of: record)
            let tokens = record.totalTokens
            summary.totalTokens += tokens
            summary.totalCost += cost
            if price.estimated { summary.costIsEstimated = true }
            summary.agentTokens[record.agent, default: 0] += tokens
            let day = calendar.startOfDay(for: record.timestamp)
            days[day, default: (0, 0)].tokens += tokens
            days[day, default: (0, 0)].cost += cost
            if period == .today, let hour = calendar.dateInterval(of: .hour, for: record.timestamp)?.start {
                hours[hour, default: (0, 0)].tokens += tokens
                hours[hour, default: (0, 0)].cost += cost
            }
            var m = models[record.model] ?? (0, 0, price.estimated)
            m.tokens += tokens
            m.cost += cost
            models[record.model] = m
            let name = record.project.isEmpty ? noProject : record.project
            var p = projects[name] ?? (0, 0, false)
            p.tokens += tokens
            p.cost += cost
            if price.estimated { p.estimated = true }
            projects[name] = p
        }
        summary.perDay = days.map { DayUsage(day: $0.key, tokens: $0.value.tokens, cost: $0.value.cost) }
            .sorted { $0.day < $1.day }
        summary.perHour = hours.map { DayUsage(day: $0.key, tokens: $0.value.tokens, cost: $0.value.cost) }
            .sorted { $0.day < $1.day }
        summary.perModel = models.map {
            ModelUsage(model: $0.key, tokens: $0.value.tokens, cost: $0.value.cost, estimated: $0.value.estimated)
        }.sorted { $0.tokens != $1.tokens ? $0.tokens > $1.tokens : $0.model < $1.model }
        summary.perProject = projects.map {
            ProjectUsage(name: $0.key, tokens: $0.value.tokens, cost: $0.value.cost, estimated: $0.value.estimated)
        }.sorted { $0.cost != $1.cost ? $0.cost > $1.cost : $0.name < $1.name }
        return summary
    }
}
