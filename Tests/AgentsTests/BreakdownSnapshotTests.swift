import AppKit
import Foundation
import SwiftUI
import Testing
@testable import AgentsFeature

/// MIS_0120: renders the two new cards to PNGs in `NSTemporaryDirectory()/mac-island-agents/` to look at them.
@MainActor @Suite struct BreakdownSnapshotTests {
    @Test func rendersTheBreakdownAndTheExtraUsageCards() throws {
        let breakdown = UsageBreakdown.build(BreakdownTests.records, hooks: ClaudeUsageParser.parse(lines: HooksTests.lines).hooks,
                                             now: HooksTests.now, window: .days7)
        let fresh = try #require(ExtraUsageParser.parse(ExtraUsageTests.json(fetchedAgo: 3600)))
        let stale = try #require(ExtraUsageParser.parse(ExtraUsageTests.json(fetchedAgo: 3 * 86_400)))
        let reached = try #require(ExtraUsageParser.parse(ExtraUsageTests.json(fetchedAgo: 600, reached: true, used: 5000)))
        let page = VStack(spacing: 12) {
            AgentsExtraUsageCard(extra: fresh, now: ExtraUsageTests.now)
            AgentsExtraUsageCard(extra: stale, now: ExtraUsageTests.now)
            AgentsExtraUsageCard(extra: reached, now: ExtraUsageTests.now)
            AgentsBreakdownCard(breakdowns: [.days7: breakdown], window: .constant(.days7))
        }
        .fixedSize(horizontal: false, vertical: true)
        let url = PageSnapshotTests.render(page, name: "breakdown", height: nil)
        #expect(url != nil)
        let empty = AgentsBreakdownCard(breakdowns: [:], window: .constant(.hours24))
        #expect(PageSnapshotTests.render(empty, name: "breakdown-empty", height: nil) != nil)
    }
}
