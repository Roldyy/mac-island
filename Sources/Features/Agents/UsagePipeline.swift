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
    /// How far back the block is looked for in the cache alone: any 5 h block is cut at the last gap of more
    /// than 5 h, which a 48 h window holds in practice.
    static let recentWindow: TimeInterval = 48 * 3600

    static func run(sources: [any UsageSource], limitSource: PlanLimitSource, planLoader: () -> PlanTier?,
                    now: Date, calendar: Calendar, shouldContinue: () -> Bool, emit: (UsageUpdate) -> Void) {
        let plan = planLoader()
        var sample = limitSource.load()
        // Nothing of the logs is known yet: a plan reading older than the 5 h window stays pending.
        emit(UsageUpdate(snapshot: nil,
                         limits: LimitsState.resolve(sample: sample, block: nil, blockKnown: false, weekTokens: 0,
                                                     weekComplete: false, now: now),
                         plan: plan, coverage: .unread, results: [], recordCount: 0, isFinal: false))

        let since = UsageSnapshot.windowStart(now: now, calendar: calendar)
        var settled: [UsageRecord] = []
        var results: [UsageLoadResult] = []
        var blockSettled = false
        // Sources run one after the other; a state reported by one source carries the records of those before it.
        for source in sources {
            var loaded = source.load(modifiedSince: since, shouldContinue: shouldContinue) { progress in
                let records = settled.isEmpty ? progress.result.records : settled + progress.result.records
                if progress.fromCache {
                    // The open block needs only the last hours of the cache: say it before the whole snapshot
                    // (13-week heatmap and all) is built, so the session ring is right at the first paint.
                    let block = UsageBlocks.active(records.filter { $0.timestamp >= now.addingTimeInterval(-recentWindow) }, now: now)
                    emit(UsageUpdate(
                        snapshot: nil,
                        limits: LimitsState.resolve(sample: sample, block: block, blockKnown: block != nil, weekTokens: 0,
                                                    weekComplete: false, now: now),
                        plan: plan, coverage: .unread, results: [], recordCount: 0, isFinal: false))
                }
                let snapshot = UsageSnapshot.build(records, now: now, calendar: calendar)
                let coverage = UsageCoverage(missingNewest: progress.missingNewest)
                // The cache says "a block is open": trusted from then on (the live session's own log is always a
                // changed file during the walk, and must not bring the placeholder back). It saying "none" is
                // not enough (a session may have started since): only a read past the last 5 h settles that.
                if progress.fromCache {
                    blockSettled = snapshot.block != nil
                } else if let pending = progress.pendingNewest, pending >= now.addingTimeInterval(-UsageBlocks.length) {
                    // some file of the last 5 h is still unread: keep what is already known
                } else {
                    blockSettled = true
                }
                let blockKnown = blockSettled
                emit(UsageUpdate(
                    snapshot: snapshot,
                    limits: LimitsState.resolve(sample: sample, block: snapshot.block, blockKnown: blockKnown,
                                                weekTokens: snapshot.week.tokens,
                                                weekComplete: coverage.covers(.week, now: now, calendar: calendar), now: now),
                    plan: plan, coverage: coverage,
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
