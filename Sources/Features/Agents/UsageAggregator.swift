import Foundation

struct DayUsage: Equatable, Identifiable, Sendable {
    var day: Date
    var tokens: Int
    var cost: Double
    /// Per model family, largest first by family order; empty when the caller did not break it down.
    var shares: [FamilyShare] = []
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
    var outputTokens = 0
    var cacheReadTokens = 0
    var cacheWriteTokens = 0
    /// What the cache reads would have cost at the plain input price, minus what they did cost.
    var cacheSavings = 0.0
}

/// Pure: every window is computed from the injected clock and calendar.
enum UsageAggregator {
    static let noProject = "Sans dossier"

    static func monthStart(containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private typealias Bucket = [ModelFamily: (tokens: Int, cost: Double)]

    private static func shares(_ bucket: Bucket) -> [FamilyShare] {
        bucket.map { FamilyShare(family: $0.key, tokens: $0.value.tokens, cost: $0.value.cost) }.sorted { $0.family < $1.family }
    }

    static func summarize(_ records: [UsageRecord], now: Date, calendar: Calendar,
                          period: UsagePeriod = .month) -> UsageSummary {
        let window = period.interval(now: now, calendar: calendar)
        var days: [Date: Bucket] = [:]
        var hours: [Date: Bucket] = [:]
        var models: [String: (tokens: Int, cost: Double, estimated: Bool)] = [:]
        var projects: [String: (tokens: Int, cost: Double, estimated: Bool)] = [:]
        var summary = UsageSummary()
        for record in records where record.timestamp >= window.start && record.timestamp < window.end {
            let price = PriceTable.price(for: record.model)
            let cost = price.perMillion.cost(of: record)
            let tokens = record.totalTokens
            let family = ModelFamily(model: record.model)
            summary.totalTokens += tokens
            summary.totalCost += cost
            summary.outputTokens += record.outputTokens
            summary.cacheReadTokens += record.cacheReadTokens
            summary.cacheWriteTokens += record.cacheCreationTokens
            summary.cacheSavings += Double(record.cacheReadTokens)
                * (price.perMillion.input - price.perMillion.cacheRead) / 1_000_000
            if price.estimated { summary.costIsEstimated = true }
            summary.agentTokens[record.agent, default: 0] += tokens
            let day = calendar.startOfDay(for: record.timestamp)
            days[day, default: [:]][family, default: (0, 0)].tokens += tokens
            days[day, default: [:]][family, default: (0, 0)].cost += cost
            if period == .today, let hour = calendar.dateInterval(of: .hour, for: record.timestamp)?.start {
                hours[hour, default: [:]][family, default: (0, 0)].tokens += tokens
                hours[hour, default: [:]][family, default: (0, 0)].cost += cost
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
        func usage(_ buckets: [Date: Bucket]) -> [DayUsage] {
            buckets.map { key, bucket in
                DayUsage(day: key, tokens: bucket.values.reduce(0) { $0 + $1.tokens },
                         cost: bucket.values.reduce(0) { $0 + $1.cost }, shares: shares(bucket))
            }.sorted { $0.day < $1.day }
        }
        summary.perDay = usage(days)
        summary.perHour = usage(hours)
        summary.perModel = models.map {
            ModelUsage(model: $0.key, tokens: $0.value.tokens, cost: $0.value.cost, estimated: $0.value.estimated)
        }.sorted { $0.tokens != $1.tokens ? $0.tokens > $1.tokens : $0.model < $1.model }
        summary.perProject = projects.map {
            ProjectUsage(name: $0.key, tokens: $0.value.tokens, cost: $0.value.cost, estimated: $0.value.estimated)
        }.sorted { $0.cost != $1.cost ? $0.cost > $1.cost : $0.name < $1.name }
        return summary
    }
}
