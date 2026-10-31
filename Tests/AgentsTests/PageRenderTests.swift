import ClaudeLiveKit
import Foundation
import SwiftUI
import Testing
@testable import AgentsFeature

/// The page as a person sees it: real NSHostingView renders in `$TMPDIR/mac-island-agents/`, named
/// `page-*.png`. The asserts only check that a non-trivial image came out; the pictures are for eyes.
@MainActor @Suite struct PageRenderTests {
    static let width: CGFloat = 692          // 720 pt panel minus the 14 pt margins
    static let viewport: CGFloat = 256       // smallest section height; the island grows to about 560

    static func page(_ model: AgentsUsageModel, live: AgentsLiveModel? = nil) -> AgentsPage {
        AgentsPage(model: model, live: live ?? PageSnapshotTests.live(), isLive: false)
    }

    @Test func firstScreenFitsTheSmallViewport() {
        let model = PageSnapshotTests.model()
        model.period = .week
        let live = PageSnapshotTests.live([
            ClaudeSession(id: "1", pid: 101, state: .working, folderName: "mac-island", entrypoint: "claude-vscode",
                          updatedAt: PageSnapshotTests.now.addingTimeInterval(-240)),
            ClaudeSession(id: "2", pid: 102, state: .waiting, folderName: "odoo-erp", entrypoint: "cli",
                          updatedAt: PageSnapshotTests.now.addingTimeInterval(-600)),
            ClaudeSession(id: "3", pid: 103, state: .idle, folderName: "site-golf", entrypoint: "cli",
                          updatedAt: PageSnapshotTests.now.addingTimeInterval(-3_600)),
        ])
        let url = OffscreenRender.png(Self.page(model, live: live), width: Self.width, height: Self.viewport, name: "page-viewport")
        #expect(url != nil)
        #expect(OffscreenRender.png(Self.page(model, live: live).page, width: Self.width, name: "page-full") != nil)
        #expect(OffscreenRender.png(Self.page(model, live: live), width: Self.width, height: 560, name: "page-tall") != nil)
        print("MIS_PNG \(OffscreenRender.directory.path)")
    }

    @Test func rendersLoadingColdPartialEstimateAndStale() {
        let now = PageSnapshotTests.now
        // Nothing yet: placeholders everywhere, no limits either.
        #expect(OffscreenRender.png(Self.page(PageSnapshotTests.model(loaded: false)), width: Self.width, height: Self.viewport,
                                    name: "page-loading") != nil)
        // Cold start half way: the plan limits and today are in, the week and month are still being read.
        let partial = AgentsUsageModel(settings: AgentsSettings(store: WindowTests.FakeStore()), sources: [],
                                       calendar: PageSnapshotTests.calendar, clock: { now })
        let today = PageSnapshotTests.records(now: now).filter { $0.timestamp >= PageSnapshotTests.calendar.startOfDay(for: now) }
        let snapshot = UsageSnapshot.build(today, now: now, calendar: PageSnapshotTests.calendar)
        let limits = LimitsState.resolve(sample: PlanLimitSample(date: now.addingTimeInterval(-90), fiveHour: 41, sevenDay: 58),
                                         block: snapshot.block, weekTokens: snapshot.week.tokens, now: now)
        partial.preload(snapshot: snapshot, limits: limits, plan: .max5x,
                        coverage: UsageCoverage(missingNewest: now.addingTimeInterval(-30 * 3600)), isRefreshing: true)
        #expect(OffscreenRender.png(Self.page(partial), width: Self.width, height: 420, name: "page-cold-partial") != nil)
        // No percentage from the plan file: the ring shows the log estimate.
        #expect(OffscreenRender.png(Self.page(PageSnapshotTests.model(limits: .some(nil))), width: Self.width, height: Self.viewport,
                                    name: "page-estimate") != nil)
        let stale = PlanLimitSample(date: now.addingTimeInterval(-7.5 * 3600), fiveHour: 91, sevenDay: 88)
        #expect(OffscreenRender.png(Self.page(PageSnapshotTests.model(limits: .some(stale))), width: Self.width, height: Self.viewport,
                                    name: "page-stale-critical") != nil)
    }
}
