import Testing
import IslandUI
@testable import IslandKit

@Suite struct ActivityArbiterTests {
    private func item(_ tag: String, _ status: IslandStatus = .neutral) -> CompactItem {
        CompactItem(symbol: "circle", text: tag, status: status)
    }

    private func activity(
        _ id: String, _ priority: ActivityPriority, leading: Bool = true, trailing: Bool = false,
        dot: Bool = false, status: IslandStatus = .neutral
    ) -> IslandActivity {
        IslandActivity(
            id: id, source: "test", priority: priority,
            leading: leading ? item("\(id).L", status) : nil,
            trailing: trailing ? item("\(id).T", status) : nil, showsDot: dot)
    }

    /// Heap's algorithm, enough for the 6-element permutation sweeps below.
    private func permutations<T>(_ input: [T]) -> [[T]] {
        var a = input
        var result: [[T]] = []
        func generate(_ k: Int) {
            if k <= 1 { result.append(a); return }
            generate(k - 1)
            for i in 0..<(k - 1) {
                a.swapAt(k.isMultiple(of: 2) ? i : 0, k - 1)
                generate(k - 1)
            }
        }
        generate(a.count)
        return result
    }

    @Test func emptyInputIsEmptyLayout() {
        #expect(ActivityArbiter.resolve([]) == .empty)
        #expect(ActivityArbiter.resolve([]).isEmpty)
    }

    @Test func priorityOrderIsAlertWaitingWorkingMusicAmbient() {
        let order: [ActivityPriority] = [.alert, .claudeWaiting, .claudeWorking, .music, .ambient]
        for (i, winner) in order.enumerated() {
            let field = order[i...].map { activity("a-\($0.rawValue)", $0) }
            #expect(ActivityArbiter.resolve(field).leading?.text == "a-\(winner.rawValue).L")
        }
    }

    @Test func eachWingHoldsOneItemFromTheBestActivityThatHasOne() {
        let claude = activity("claude", .claudeWorking, leading: true, trailing: false)
        let music = activity("music", .music, leading: true, trailing: true)
        let layout = ActivityArbiter.resolve([music, claude])
        #expect(layout.leading?.text == "claude.L")
        #expect(layout.trailing?.text == "music.T", "free wing goes to the next activity")
        #expect(layout.dot == nil)
    }

    @Test func sameRankTiesBreakByIdAscending() {
        let layout = ActivityArbiter.resolve([activity("b", .music), activity("c", .music), activity("a", .music)])
        #expect(layout.leading?.text == "a.L")
    }

    @Test func losingActivityWithDotFallsBackToTheDot() {
        let winner = activity("w", .alert, leading: true, trailing: true)
        let loser = activity("l", .claudeWaiting, leading: true, trailing: true, dot: true, status: .warning)
        let layout = ActivityArbiter.resolve([loser, winner])
        #expect(layout.leading?.text == "w.L")
        #expect(layout.trailing?.text == "w.T")
        #expect(layout.dot == .warning)
    }

    @Test func losingActivityWithoutDotFlagVanishes() {
        let layout = ActivityArbiter.resolve([
            activity("w", .alert, trailing: true),
            activity("l", .music, trailing: true, status: .danger),
        ])
        #expect(layout.dot == nil)
    }

    @Test func activityThatFitsItsWingNeverAddsADot() {
        let layout = ActivityArbiter.resolve([activity("a", .alert, dot: true, status: .danger)])
        #expect(layout.leading != nil)
        #expect(layout.dot == nil)
    }

    @Test func itemlessActivityWithDotYieldsOnlyADot() {
        let a = IslandActivity(id: "a", source: "s", priority: .alert, showsDot: true)
        let layout = ActivityArbiter.resolve([a])
        #expect(layout.leading == nil && layout.trailing == nil)
        #expect(layout.dot == .neutral)
    }

    @Test func dotShowsTheHighestSeverityOnly() {
        let wing = activity("w", .alert, leading: true, trailing: true)
        let field = [
            wing,
            activity("a", .music, dot: true, status: .info),
            activity("b", .claudeWorking, dot: true, status: .danger),
            activity("c", .claudeWaiting, dot: true, status: .warning),
        ]
        #expect(ActivityArbiter.resolve(field).dot == .danger)
        for order in permutations(field) { #expect(ActivityArbiter.resolve(order).dot == .danger) }
    }

    @Test func severityIsStrictlyOrdered() {
        let ordered: [IslandStatus] = [.neutral, .success, .info, .warning, .danger]
        let ranks = ordered.map(ActivityArbiter.severity)
        #expect(Set(ranks).count == IslandStatus.allCases.count)
        #expect(ranks == ranks.sorted())
    }

    @Test func everyPermutationOfDistinctIdsGivesTheSameLayout() {
        let field = [
            activity("a", .music, leading: true, trailing: true),
            activity("b", .claudeWorking, leading: true, trailing: false),
            activity("c", .claudeWorking, leading: true, trailing: true, dot: true, status: .info),
            activity("d", .ambient, leading: false, trailing: true, dot: true, status: .warning),
            activity("e", .alert, leading: false, trailing: true),
            activity("f", .claudeWaiting, leading: true, trailing: false, dot: true, status: .danger),
        ]
        let baseline = ActivityArbiter.resolve(field)
        let perms = permutations(field)
        #expect(perms.count == 720)
        for p in perms { #expect(ActivityArbiter.resolve(p) == baseline) }
        #expect(ActivityArbiter.resolve(field) == baseline, "calling twice changes nothing")
    }

    @Test func randomFieldsMatchAnIndependentOracleAndNeverDuplicateAnItem() {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(bound))
        }
        let statuses = IslandStatus.allCases
        let priorities: [ActivityPriority] = [.ambient, .music, .claudeWorking, .claudeWaiting, .alert]
        for _ in 0..<500 {
            let count = next(7)
            let field = (0..<count).map { i in
                activity("id\(i)", priorities[next(5)], leading: next(2) == 0, trailing: next(2) == 0,
                         dot: next(2) == 0, status: statuses[next(statuses.count)])
            }
            let layout = ActivityArbiter.resolve(field)
            let ranked = field.sorted { $0.priority != $1.priority ? $0.priority > $1.priority : $0.id < $1.id }
            #expect(layout.leading == ranked.compactMap(\.leading).first)
            #expect(layout.trailing == ranked.compactMap(\.trailing).first)
            // Unique tags: the same text in both wings would mean one item drew twice.
            if let l = layout.leading, let t = layout.trailing { #expect(l.text != t.text) }
            if field.isEmpty { #expect(layout == .empty) }
            // A dot appears exactly when a dot-flagged activity lost a wing or had none.
            let anyDot = field.contains { a in
                a.showsDot && ((a.leading == nil && a.trailing == nil)
                    || (a.leading != nil && layout.leading != a.leading)
                    || (a.trailing != nil && layout.trailing != a.trailing))
            }
            #expect((layout.dot != nil) == anyDot)
        }
    }

    @Test func duplicateIdsCountOnce() {
        let a = activity("same", .alert)
        let b = activity("same", .alert, leading: false, trailing: true)
        let layout = ActivityArbiter.resolve([a, b])
        #expect(layout.leading != nil && layout.trailing == nil)
    }
}
