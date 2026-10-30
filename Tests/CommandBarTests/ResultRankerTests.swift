import Foundation
import Testing
@testable import CommandBarFeature

@Suite struct ResultRankerTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func nonSubsequenceDoesNotMatch() {
        #expect(ResultRanker.fuzzyScore(query: "xyz", text: "Safari") == nil)
        #expect(ResultRanker.fuzzyScore(query: "safarii", text: "Safari") == nil)
    }

    @Test func caseAndDiacriticsAreIgnored() {
        #expect(ResultRanker.fuzzyScore(query: "ecran", text: "\u{00C9}cran") != nil)
        #expect(ResultRanker.fuzzyScore(query: "SAF", text: "safari") != nil)
    }

    @Test func orderingOfMatchQuality() throws {
        let exact = try #require(ResultRanker.fuzzyScore(query: "mail", text: "Mail"))
        let prefix = try #require(ResultRanker.fuzzyScore(query: "mai", text: "Mail"))
        let wordStart = try #require(ResultRanker.fuzzyScore(query: "pre", text: "System Preferences"))
        let inner = try #require(ResultRanker.fuzzyScore(query: "ref", text: "System Preferences"))
        let scattered = try #require(ResultRanker.fuzzyScore(query: "sfr", text: "Safari"))
        #expect(exact > prefix)
        #expect(prefix > wordStart)
        #expect(wordStart > inner)
        #expect(inner > scattered)
    }

    @Test func prefixBeatsInnerMatch() {
        let ranked = ResultRanker.rank([result("b", "Photos Booth"), result("a", "Booth Photos")],
                                       query: "boo", now: now)
        #expect(ranked.map(\.id) == ["a", "b"])
    }

    @Test func nonMatchesAreDropped() {
        let ranked = ResultRanker.rank([result("a", "Safari"), result("b", "Mail")], query: "saf", now: now)
        #expect(ranked.map(\.id) == ["a"])
    }

    @Test func keywordsMatchButWeighLessThanTitle() {
        let items = [result("k", "Toggle Night Shift", keywords: ["dark"]),
                     result("t", "Dark Mode")]
        #expect(ResultRanker.rank(items, query: "dark", now: now).map(\.id) == ["t", "k"])
        #expect(ResultRanker.rank([items[0]], query: "dark", now: now).map(\.id) == ["k"])
    }

    @Test func habitBoostReordersCloseMatches() {
        let items = [result("a", "Notes"), result("b", "Notion")]
        let plain = ResultRanker.rank(items, query: "not", now: now)
        #expect(plain.map(\.id) == ["a", "b"])                       // tie: title order
        let habits = HabitWeights(weight: { $0 == "b" ? 8 : 0 }, lastUsed: { _ in nil })
        #expect(ResultRanker.rank(items, query: "not", habits: habits, now: now).map(\.id) == ["b", "a"])
    }

    @Test func habitDoesNotRescueANonMatch() {
        let habits = HabitWeights(weight: { _ in 1000 }, lastUsed: { _ in self.now })
        #expect(ResultRanker.rank([result("a", "Safari")], query: "zzz", habits: habits, now: now).isEmpty)
    }

    @Test func recencyBreaksTiesAndFades() {
        let items = [result("a", "Notes"), result("b", "Notion")]
        let recent = HabitWeights(weight: { _ in 0 },
                                  lastUsed: { $0 == "b" ? self.now.addingTimeInterval(-60) : nil })
        #expect(ResultRanker.rank(items, query: "not", habits: recent, now: now).map(\.id) == ["b", "a"])
        let old = HabitWeights(weight: { _ in 0 },
                               lastUsed: { $0 == "b" ? self.now.addingTimeInterval(-86_400 * 400) : nil })
        let boostOld = ResultRanker.score(items[1], query: "not", habits: old, now: now) ?? 0
        let boostNone = ResultRanker.score(items[1], query: "not", habits: .none, now: now) ?? 0
        #expect(boostOld - boostNone < 0.01)
    }

    @Test func fixedScoresPinCalculatorFirstAndWebLast() {
        let items = [result("web", "Search", kind: .web, fixed: -1000), result("a", "Safari"),
                     result("calc", "= 4", kind: .calculator, fixed: 1000)]
        #expect(ResultRanker.rank(items, query: "saf", now: now).map(\.id) == ["calc", "a", "web"])
    }

    @Test func orderingIsStableWhateverTheInputOrder() {
        let items = (0..<6).map { result("id\($0)", "Note \($0 % 2)") }
        let expected = ResultRanker.rank(items, query: "note", now: now).map(\.id)
        for _ in 0..<20 {
            #expect(ResultRanker.rank(items.shuffled(), query: "note", now: now).map(\.id) == expected)
        }
    }

    @Test func limitIsApplied() {
        let items = (0..<30).map { result("id\($0)", "App \($0)") }
        #expect(ResultRanker.rank(items, query: "app", now: now, limit: 8).count == 8)
    }

    @Test func emptyQueryShowsOnlyHabitItems() {
        let items = [result("a", "Safari"), result("b", "Mail"), result("c", "Notes")]
        let habits = HabitWeights(weight: { $0 == "c" ? 3 : ($0 == "b" ? 1 : 0) }, lastUsed: { _ in nil })
        #expect(ResultRanker.rank(items, query: "", habits: habits, now: now).map(\.id) == ["c", "b"])
        #expect(ResultRanker.rank(items, query: "  ", habits: .none, now: now).isEmpty)
    }
}
