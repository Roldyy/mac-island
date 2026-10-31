import Foundation

/// One published state of a refresh. Self-contained, so a consumer that skipped one still has everything.
struct UsageUpdate: Sendable {
    /// nil for the very first update: only the (cheap) plan limits are known.
    var snapshot: UsageSnapshot?
    var limits: LimitsState
    var plan: PlanTier?
    var coverage: UsageCoverage
    /// Counts only, records emptied.
    var results: [UsageLoadResult]
    var recordCount: Int
    var isFinal: Bool
}

/// The off-main-actor part of a refresh: limits first, then every state the sources report, then the end state.
enum UsagePipeline {
    static func run(sources: [any UsageSource], limitSource: PlanLimitSource, planLoader: () -> PlanTier?,
                    now: Date, calendar: Calendar, shouldContinue: () -> Bool, emit: (UsageUpdate) -> Void) {
        let plan = planLoader()
        var sample = limitSource.load()
        emit(UsageUpdate(snapshot: nil, limits: LimitsState.resolve(sample: sample, block: nil, weekTokens: 0, now: now),
                         plan: plan, coverage: .unread, results: [], recordCount: 0, isFinal: false))

        let since = UsageSnapshot.windowStart(now: now, calendar: calendar)
        var settled: [UsageRecord] = []
        var results: [UsageLoadResult] = []
        // Sources run one after the other; a state reported by one source carries the records of those before it.
        for source in sources {
            var loaded = source.load(modifiedSince: since, shouldContinue: shouldContinue) { progress in
                let records = settled + progress.result.records
                let snapshot = UsageSnapshot.build(records, now: now, calendar: calendar)
                emit(UsageUpdate(
                    snapshot: snapshot,
                    limits: LimitsState.resolve(sample: sample, block: snapshot.block, weekTokens: snapshot.week.tokens, now: now),
                    plan: plan, coverage: UsageCoverage(missingNewest: progress.missingNewest),
                    results: results + [counts(progress.result)], recordCount: records.count, isFinal: false))
            }
            settled.append(contentsOf: loaded.records)
            loaded.records = []
            results.append(loaded)
        }
        guard shouldContinue() else { return }
        sample = limitSource.load()
        let snapshot = UsageSnapshot.build(settled, now: now, calendar: calendar)
        emit(UsageUpdate(
            snapshot: snapshot,
            limits: LimitsState.resolve(sample: sample, block: snapshot.block, weekTokens: snapshot.week.tokens, now: now),
            plan: plan, coverage: .complete, results: results, recordCount: settled.count, isFinal: true))
    }

    private static func counts(_ result: UsageLoadResult) -> UsageLoadResult {
        var copy = result
        copy.records = []
        return copy
    }
}
