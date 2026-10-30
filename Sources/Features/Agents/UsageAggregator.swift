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

struct UsageSummary: Equatable, Sendable {
    var totalTokens = 0
    var totalCost = 0.0
    var costIsEstimated = false
    var perDay: [DayUsage] = []
    var perModel: [ModelUsage] = []
}

/// Pure: period = the calendar month containing `now`, in the injected calendar.
enum UsageAggregator {
    static func monthStart(containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func summarize(_ records: [UsageRecord], now: Date, calendar: Calendar) -> UsageSummary {
        guard let month = calendar.dateInterval(of: .month, for: now) else { return UsageSummary() }
        var days: [Date: (tokens: Int, cost: Double)] = [:]
        var models: [String: (tokens: Int, cost: Double, estimated: Bool)] = [:]
        var summary = UsageSummary()
        for record in records where record.timestamp >= month.start && record.timestamp < month.end {
            let price = PriceTable.price(for: record.model)
            let cost = price.perMillion.cost(of: record)
            let tokens = record.totalTokens
            summary.totalTokens += tokens
            summary.totalCost += cost
            if price.estimated { summary.costIsEstimated = true }
            let day = calendar.startOfDay(for: record.timestamp)
            days[day, default: (0, 0)].tokens += tokens
            days[day, default: (0, 0)].cost += cost
            var m = models[record.model] ?? (0, 0, price.estimated)
            m.tokens += tokens
            m.cost += cost
            models[record.model] = m
        }
        summary.perDay = days.map { DayUsage(day: $0.key, tokens: $0.value.tokens, cost: $0.value.cost) }
            .sorted { $0.day < $1.day }
        summary.perModel = models.map {
            ModelUsage(model: $0.key, tokens: $0.value.tokens, cost: $0.value.cost, estimated: $0.value.estimated)
        }.sorted { $0.tokens != $1.tokens ? $0.tokens > $1.tokens : $0.model < $1.model }
        return summary
    }
}
