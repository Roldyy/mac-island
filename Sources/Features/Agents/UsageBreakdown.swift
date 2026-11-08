import Foundation

/// The three windows of the breakdown card. Rolling, like Claude Code's own /usage screen, and filtered by the
/// timestamp of each log line (never by file date: a subagent log outlives its window).
enum BreakdownWindow: String, CaseIterable, Identifiable, Sendable {
    case hours24, days7, days30

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .hours24: 24 * 3600
        case .days7: 7 * 24 * 3600
        case .days30: 30 * 24 * 3600
        }
    }

    var title: String {
        switch self {
        case .hours24: "24 h"
        case .days7: "7 j"
        case .days30: "30 j"
        }
    }
}

struct BreakdownModelShare: Equatable, Sendable {
    var family: ModelFamily
    /// 0...1 of the row's own weight.
    var share: Double
}

struct BreakdownRow: Equatable, Identifiable, Sendable {
    var name: String
    var weight: Double
    /// 0...1 of every request of the window, as /usage divides it. Shares of two categories overlap.
    var share: Double
    var models: [BreakdownModelShare]
    var id: String { name }
}

struct BreakdownHookRow: Equatable, Identifiable, Sendable {
    var name: String
    var runs: Int
    var totalMs: Int
    var errors: Int
    var id: String { name }
}

struct BreakdownCLIRow: Equatable, Identifiable, Sendable {
    var name: String
    var calls: Int
    var id: String { name }
}

/// "What contributes to my usage": per subagent, MCP server, skill, plugin and CLI binary, each with the model
/// mix behind it. An estimate: it uses the weights Claude Code's /usage screen uses (read from its binary, 2.1.319),
/// which are not documented and can change; a tool call has no tokens of its own, so the CLI list is counts only.
struct UsageBreakdown: Equatable, Sendable {
    static let mainSession = "Session principale"

    var totalWeight = 0.0
    var subagents: [BreakdownRow] = []
    var mcpServers: [BreakdownRow] = []
    var skills: [BreakdownRow] = []
    var plugins: [BreakdownRow] = []
    var cli: [BreakdownCLIRow] = []
    /// Hooks spend no tokens: runs, time and errors, never a share.
    var hooks: [BreakdownHookRow] = []

    var isEmpty: Bool { totalWeight == 0 && hooks.isEmpty }

    /// (cache_read + input*10 + cache_creation*12.5 + output*50) * tier.
    static func weight(of record: UsageRecord) -> Double {
        let base = Double(record.cacheReadTokens) + Double(record.inputTokens) * 10
            + Double(record.cacheCreationTokens) * 12.5 + Double(record.outputTokens) * 50
        return base * tier(model: record.model)
    }

    /// haiku 1, opus 5, fable 10, anything else (sonnet included) 3.
    static func tier(model: String) -> Double {
        let name = model.lowercased()
        if name.contains("haiku") { return 1 }
        if name.contains("opus") { return 5 }
        if name.contains("fable") { return 10 }
        return 3
    }

    private struct Bucket {
        var weight = 0.0
        var families: [ModelFamily: Double] = [:]
    }

    static func build(_ records: [UsageRecord], hooks: [HookRun] = [], now: Date, window: BreakdownWindow) -> UsageBreakdown {
        let start = now.addingTimeInterval(-window.seconds)
        var total = 0.0
        var agents: [String: Bucket] = [:], servers: [String: Bucket] = [:]
        var skills: [String: Bucket] = [:], plugins: [String: Bucket] = [:]
        var binaries: [String: Int] = [:]
        var families: [String: ModelFamily] = [:]

        func add(_ key: String, weight: Double, family: ModelFamily, to table: inout [String: Bucket]) {
            var bucket = table[key] ?? Bucket()
            bucket.weight += weight
            bucket.families[family, default: 0] += weight
            table[key] = bucket
        }

        for record in records where record.timestamp >= start && record.timestamp <= now {
            let weight = Self.weight(of: record)
            let family: ModelFamily
            if let known = families[record.model] { family = known } else {
                family = ModelFamily(model: record.model)
                families[record.model] = family
            }
            total += weight
            // Every request lands in exactly one row of the first list, so its rows add up to the total.
            add(record.attributionAgent ?? mainSession, weight: weight, family: family, to: &agents)
            if let name = record.attributionMcpServer { add(name, weight: weight, family: family, to: &servers) }
            if let name = record.attributionSkill { add(name, weight: weight, family: family, to: &skills) }
            if let name = record.attributionPlugin { add(name, weight: weight, family: family, to: &plugins) }
            for binary in record.cliBinaries { binaries[binary, default: 0] += 1 }
        }

        var hookTable: [String: BreakdownHookRow] = [:]
        for hook in hooks where hook.timestamp >= start && hook.timestamp <= now {
            var row = hookTable[hook.name] ?? BreakdownHookRow(name: hook.name, runs: 0, totalMs: 0, errors: 0)
            row.runs += 1
            row.totalMs += hook.durationMs
            if hook.failed { row.errors += 1 }
            hookTable[hook.name] = row
        }

        func rows(_ table: [String: Bucket]) -> [BreakdownRow] {
            table.map { name, bucket in
                BreakdownRow(
                    name: name, weight: bucket.weight, share: total > 0 ? bucket.weight / total : 0,
                    models: bucket.families.map {
                        BreakdownModelShare(family: $0.key, share: bucket.weight > 0 ? $0.value / bucket.weight : 0)
                    }.sorted { $0.family < $1.family })
            }.sorted { $0.weight != $1.weight ? $0.weight > $1.weight : $0.name < $1.name }
        }

        var result = UsageBreakdown()
        result.totalWeight = total
        result.subagents = rows(agents)
        result.mcpServers = rows(servers)
        result.skills = rows(skills)
        result.plugins = rows(plugins)
        result.hooks = hookTable.values.sorted { $0.runs != $1.runs ? $0.runs > $1.runs : $0.name < $1.name }
        result.cli = binaries.map { BreakdownCLIRow(name: $0.key, calls: $0.value) }
            .sorted { $0.calls != $1.calls ? $0.calls > $1.calls : $0.name < $1.name }
        return result
    }
}
