import AppKit
import ClaudeLiveKit
import Foundation
import SwiftUI
import Testing
@testable import AgentsFeature

/// The page at the width the island really gives it, and at a narrower and a wider one. PNGs land in
/// `$TMPDIR/mac-island-agents/` named `rw-<state>-<width>.png`; the asserts are about layout (nothing wraps
/// into a squeezed column, nothing grows with a long name or a big number, nothing overflows its width).
@MainActor @Suite struct RealWidthRenderTests {
    /// 592 pt page body minus 14 pt of padding each side (`HomeGeometry.pageBodyWidth`, `HomePageView`).
    static let realWidth: CGFloat = 564
    static let widths: [CGFloat] = [480, realWidth, 640]
    static let now = PageSnapshotTests.now
    static var calendar: Calendar { PageSnapshotTests.calendar }

    static func page(_ model: AgentsUsageModel, live: AgentsLiveModel? = nil) -> AgentsPage {
        AgentsPage(model: model, live: live ?? PageSnapshotTests.live(), isLive: false)
    }

    static func model(records: [UsageRecord], sample: PlanLimitSample?, plan: PlanTier? = .max5x,
                      period: UsagePeriod = .month) -> AgentsUsageModel {
        let model = AgentsUsageModel(settings: AgentsSettings(store: WindowTests.FakeStore()), sources: [],
                                     calendar: calendar, clock: { now })
        let snapshot = UsageSnapshot.build(records, now: now, calendar: calendar)
        let state = LimitsState.resolve(sample: sample, block: snapshot.block, weekTokens: snapshot.week.tokens, now: now)
        model.preload(snapshot: snapshot, limits: state, plan: plan, status: records.isEmpty ? .empty : .ready)
        model.period = period
        return model
    }

    static let fresh = PlanLimitSample(date: now.addingTimeInterval(-90), fiveHour: 3, sevenDay: 58)

    static func size<V: View>(_ view: V, width: CGFloat) -> CGSize {
        _ = NSApplication.shared
        // Width pinned, height free: the fitting height is what the content needs at that width.
        let hosting = NSHostingView(rootView: view.frame(width: width).environment(\.agentsSettled, true))
        return hosting.fittingSize
    }

    static func sessions() -> [ClaudeSession] {
        let states: [ClaudeSession.State] = [.working, .waiting, .idle]
        let folders = ["mac-island", "odoo-erp", "site-golf"]
        var out: [ClaudeSession] = []
        for index in 0..<3 {
            out.append(ClaudeSession(id: "\(index)", pid: Int32(101 + index), state: states[index], folderName: folders[index],
                                     entrypoint: "cli", updatedAt: now.addingTimeInterval(-Double(index + 1) * 300)))
        }
        return out
    }

    static func record(_ model: String, project: String, tokens: Int, minutesAgo: Int) -> UsageRecord {
        UsageRecord(messageID: nil, model: model, timestamp: now.addingTimeInterval(Double(-minutesAgo) * 60),
                    inputTokens: tokens / 10, outputTokens: tokens / 10, cacheCreationTokens: tokens / 10,
                    cacheReadTokens: tokens - 3 * (tokens / 10), project: project)
    }

    // MARK: pictures

    @Test func rendersEveryStateAtEveryWidth() {
        for width in Self.widths {
            let w = Int(width)
            let standard = Self.page(PageSnapshotTests.model())
            #expect(OffscreenRender.png(standard.page, width: width, name: "rw-month-\(w)") != nil)
            #expect(OffscreenRender.png(standard, width: width, height: 256, name: "rw-viewport-\(w)") != nil)
            #expect(OffscreenRender.png(Self.page(PageSnapshotTests.model(loaded: false)).page, width: width, name: "rw-loading-\(w)") != nil)
            #expect(OffscreenRender.png(Self.page(PageSnapshotTests.model(limits: .some(nil))).page, width: width,
                                        name: "rw-estimate-\(w)") != nil)
            let stale = PlanLimitSample(date: Self.now.addingTimeInterval(-9 * 3600), fiveHour: 91, sevenDay: 88)
            #expect(OffscreenRender.png(Self.page(PageSnapshotTests.model(limits: .some(stale))).page, width: width,
                                        name: "rw-stale-\(w)") != nil)
            #expect(OffscreenRender.png(Self.page(PageSnapshotTests.model(), live: PageSnapshotTests.live([])).page, width: width,
                                        name: "rw-nosession-\(w)") != nil)
            #expect(OffscreenRender.png(Self.page(PageSnapshotTests.model(), live: PageSnapshotTests.live(Self.sessions())).page, width: width,
                                        name: "rw-3sessions-\(w)") != nil)
            let today = PageSnapshotTests.model()
            today.period = .today
            #expect(OffscreenRender.png(Self.page(today).page, width: width, name: "rw-today-\(w)") != nil)
        }
        print("MIS_PNG \(OffscreenRender.directory.path)")
    }

    @Test func rendersLongNamesAndHugeNumbers() {
        let long = "a-very-long-client-project-name-that-keeps-going-and-going"
        var records = PageSnapshotTests.records(now: Self.now)
        records.append(Self.record("claude-opus-4-5", project: long, tokens: 10_000_000_000, minutesAgo: 30))
        records.append(Self.record("claude-sonnet-4-5", project: "second-long-project-folder-name-2026", tokens: 800_000_000, minutesAgo: 600))
        for count in 0..<12 { records.append(Self.record("claude-haiku-4-5", project: "extra-\(count)", tokens: 1_000_000, minutesAgo: 20 + count)) }
        let model = Self.model(records: records, sample: Self.fresh)
        for width in Self.widths {
            #expect(OffscreenRender.png(Self.page(model).page, width: width, name: "rw-huge-\(Int(width))") != nil)
        }
        let expanded = AgentsShareCard(card: .projects, rows: model.summary.perProject.map {
            ShareRow(name: $0.name, tokens: $0.tokens, cost: $0.cost, estimated: $0.estimated)
        }, expanded: true)
        #expect(OffscreenRender.png(expanded, width: Self.realWidth - 24, name: "rw-expanded-projects") != nil)
    }

    /// Needs this Mac's real logs (`MIS_REAL_DATA=1`); names stay inside the PNG, nothing is printed.
    @Test(.enabled(if: RealDataTests.enabled)) func rendersTheRealDataAtTheRealWidth() {
        let calendar = Self.calendar
        let now = Date()
        let since = UsageSnapshot.windowStart(now: now, calendar: calendar)
        let store = UsageCacheStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("mis-rw-\(UUID().uuidString)").appendingPathComponent("usage-cache.bin"))
        defer { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
        let records = ClaudeUsageSource(store: store).load(modifiedSince: since).records
        let snapshot = UsageSnapshot.build(records, now: now, calendar: calendar)
        for (name, sample) in [("real", PlanLimitSource().load()), ("real-estimate", nil)] {
            let model = AgentsUsageModel(settings: AgentsSettings(store: WindowTests.FakeStore()), sources: [], calendar: calendar,
                                         clock: { now })
            let state = LimitsState.resolve(sample: sample, block: snapshot.block, weekTokens: snapshot.week.tokens, now: now)
            model.preload(snapshot: snapshot, limits: state, plan: PlanTierSource.load(), status: .ready)
            model.period = .month
            for width in Self.widths {
                #expect(OffscreenRender.png(Self.page(model, live: PageSnapshotTests.live([])).page, width: width,
                                            name: "rw-\(name)-\(Int(width))") != nil)
            }
        }
    }

    // MARK: layout asserts

    @Test func theHeroNeverSqueezesItsTextAtAnyWidth() {
        let snapshot = UsageSnapshot.build(PageSnapshotTests.records(now: Self.now), now: Self.now, calendar: Self.calendar)
        let states: [(String, PlanLimitSample?)] = [("plan", Self.fresh), ("estimate", nil),
            ("stale", PlanLimitSample(date: Self.now.addingTimeInterval(-9 * 3600), fiveHour: 91, sevenDay: 88))]
        for (name, sample) in states {
            let state = LimitsState.resolve(sample: sample, block: snapshot.block, weekTokens: snapshot.week.tokens, now: Self.now)
            for width in Self.widths {
                let card = AgentsHeroCard(limits: state, display: .remaining, now: Self.now, isLoaded: true, ticking: false)
                let fit = Self.size(card, width: width - 24)
                // Squeezed text wraps and the card grows past the stacked layout (ring over its words, about 250 pt).
                #expect(fit.height <= 280, "\(name) \(Int(width)) pt: hero is \(Int(fit.height)) pt tall")
                #expect(fit.width <= width - 24 + 0.5, "\(name) \(Int(width)) pt: hero is \(Int(fit.width)) pt wide")
            }
        }
    }

    @Test func aLongNameOrAHugeCostNeverGrowsAShareRow() {
        let short = [ShareRow(name: "mac-island", tokens: 5_000_000, cost: 12.5, estimated: false)]
        let stress = [ShareRow(name: String(repeating: "very-long-project-name-", count: 4), tokens: 10_000_000_000,
                               cost: 12_345.67, estimated: true)]
        for width in Self.widths {
            for card in [AgentsCard.projects, .models] {
                let base = Self.size(AgentsShareCard(card: card, rows: short), width: width - 24)
                let tall = Self.size(AgentsShareCard(card: card, rows: stress), width: width - 24)
                #expect(abs(base.height - tall.height) < 0.5, "\(card) \(Int(width)) pt: \(base.height) vs \(tall.height)")
                #expect(tall.width <= width - 24 + 0.5)
            }
        }
    }

    @Test func spendTodayAndActivityCardsKeepTheirHeightWithHugeNumbers() {
        let small = UsageSummary(totalTokens: 5_000, totalCost: 1.5)
        let huge = UsageSummary(totalTokens: 10_000_000_000, totalCost: 12_345.67, costIsEstimated: false)
        for width in Self.widths {
            let w = width - 24
            func spend(_ summary: UsageSummary) -> CGSize {
                Self.size(AgentsSpendCard(summary: summary, period: .month, plan: nil, todayCost: 0, todayEstimated: false,
                                          dailyBudget: nil), width: w)
            }
            #expect(abs(spend(small).height - spend(huge).height) < 0.5, "spend \(Int(width)) pt")
            func today(_ summary: UsageSummary) -> CGSize {
                Self.size(AgentsTodayCard(summary: summary, hourly: [1, 2, 3], isReady: true), width: w)
            }
            #expect(abs(today(small).height - today(huge).height) < 0.5, "today \(Int(width)) pt")
            #expect(today(huge).width <= w + 0.5)
        }
    }

    @Test func theWholePageNeverOverflowsItsWidth() {
        for width in Self.widths {
            let fit = Self.size(Self.page(PageSnapshotTests.model()).page, width: width)
            #expect(fit.width <= width + 0.5, "page \(Int(width)) pt is \(Int(fit.width)) pt wide")
        }
    }

    @Test func cardsOnlyPairUpOnAWidePage() {
        let cards: [AgentsCard] = [.spend, .models, .projects]
        #expect(AgentsCardLayout.rows(cards, width: 540) == [[.spend], [.models], [.projects]])
        #expect(AgentsCardLayout.rows(cards, width: 800) == [[.spend, .models], [.projects]])
    }
}
