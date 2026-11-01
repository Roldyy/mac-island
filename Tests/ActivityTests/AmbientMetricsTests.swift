import Foundation
import IslandUI
import Testing
@testable import IslandKit

@Suite struct AmbientMetricsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ id: String, text: String? = nil, clock: Date? = nil, progress: Double? = nil) -> AmbientIndicator {
        AmbientIndicator(id: id, symbol: "circle", text: text, progress: progress, clockSince: clock)
    }

    private func content(_ lead: [AmbientIndicator], _ trail: [AmbientIndicator]) -> ClosedIslandContent {
        ClosedIslandContent(leading: lead, trailing: trail)
    }

    // MARK: Element and group widths

    @Test func textWidthGrowsWithTheText() {
        #expect(AmbientMetrics.textWidth("") == 0)
        #expect(AmbientMetrics.textWidth("58%") > AmbientMetrics.textWidth("8%"))
        #expect(AmbientMetrics.textWidth("100%") > AmbientMetrics.textWidth("58%"))
    }

    @Test func aGlyphAloneIsAsWideAsItsFrame() {
        #expect(AmbientMetrics.elementWidth(item("a"), now: now) == AmbientMetrics.glyphSize)
    }

    @Test func aValueAddsAGapAndItsText() {
        let width = AmbientMetrics.elementWidth(item("a", text: "82%"), now: now)
        #expect(width == AmbientMetrics.glyphSize + AmbientMetrics.iconGap + AmbientMetrics.textWidth("82%"))
    }

    @Test func aLongTitleIsCappedAtItsSlot() {
        let title = String(repeating: "Mmmm ", count: 20)
        #expect(AmbientMetrics.textSlot(item("m", text: title), now: now) == AmbientMetrics.maxTextWidth)
    }

    @Test func groupWidthAddsGapsBetweenElementsOnly() {
        let a = item("a"), b = item("b")
        #expect(AmbientMetrics.groupWidth([], now: now) == 0)
        #expect(AmbientMetrics.groupWidth([a], now: now) == AmbientMetrics.glyphSize)
        #expect(AmbientMetrics.groupWidth([a, b], now: now) == 2 * AmbientMetrics.glyphSize + AmbientMetrics.elementGap)
    }

    // MARK: Clock reservation

    @Test func theClockReservesItsWorstCaseSoNothingJumps() {
        let early = now.addingTimeInterval(-5), later = now.addingTimeInterval(-599)
        #expect(AmbientMetrics.textSlot(item("c", clock: early), now: now) == AmbientMetrics.textSlot(item("c", clock: later), now: now))
        let hour = now.addingTimeInterval(-3700)
        #expect(AmbientMetrics.textSlot(item("c", clock: hour), now: now) > AmbientMetrics.textSlot(item("c", clock: early), now: now))
    }

    @Test func theClockAsksToBeRemeasuredWhenItWidens() {
        let since = now.addingTimeInterval(-3000)
        #expect(AmbientMetrics.secondsUntilClockWidens(since: since, now: now) == 600)
        #expect(AmbientMetrics.secondsUntilClockWidens(since: now.addingTimeInterval(-4000), now: now) == nil)
    }

    // MARK: Closed width

    @Test func anEmptyIslandAddsNothing() {
        #expect(AmbientMetrics.notchedExtent(.empty, now: now) == 0)
        #expect(AmbientMetrics.pillExtent(.empty, now: now) == 0)
        #expect(AmbientMetrics.measuringItem(forExtent: 0) == nil)
    }

    @Test func aNotchedWingGrowsOnlyAsMuchAsItsOwnSideNeeds() {
        let one = content([item("a", text: "58%")], [])
        let need = AmbientMetrics.groupWidth(one.leading, now: now) + 2 * AmbientMetrics.wingPadding - NotchGeometry.baseWing
        #expect(AmbientMetrics.notchedExtent(one, now: now) == need.rounded(.up))
        // An empty side asks for nothing, and a narrower side does not borrow the wider one's extent.
        let sides = AmbientMetrics.notchedExtents(one, now: now)
        #expect(sides.leading == need.rounded(.up) && sides.trailing == 0)
        let both = content([item("a", text: "58%")], [item("b")])
        let bothSides = AmbientMetrics.notchedExtents(both, now: now)
        #expect(bothSides.leading == sides.leading)
        #expect(bothSides.trailing > 0 && bothSides.trailing < bothSides.leading)
        #expect(AmbientMetrics.notchedExtent(both, now: now) == bothSides.leading)
    }

    @Test func aPillAsksTheSameOnBothSides() {
        let c = content([item("a", text: "Mmmmmmmmmm"), item("a2", text: "Mmmmmmmmmm")], [])
        let sides = AmbientMetrics.extents(c, notched: false, now: now)
        #expect(sides.leading == sides.trailing && sides.leading == AmbientMetrics.pillExtent(c, now: now))
    }

    @Test func aDotAloneAsksForARightWingOnly() {
        let sides = AmbientMetrics.notchedExtents(ClosedIslandContent(leading: [], trailing: [], dot: .warning), now: now)
        #expect(sides.leading == 0 && sides.trailing == AmbientMetrics.dotExtent)
    }

    @Test func aNotchedWingNeverExceedsTheGeometryCap() {
        let wide = content([item("a", text: "Mmmmmmmmmm"), item("b", text: "Mmmmmmmmmm")], [])
        #expect(AmbientMetrics.notchedExtent(wide, now: now) == NotchGeometry.maxWingExtent)
    }

    @Test func fourCompactIndicatorsFitThePillWithoutGrowing() {
        let four = content([item("a", text: "58%"), item("b", progress: 0.5)], [item("c", text: "82%"), item("d")])
        #expect(AmbientMetrics.groupWidth(four.all, now: now) + AmbientMetrics.groupGap + 2 * AmbientMetrics.pillPadding
                <= NotchGeometry.pillWidth + 2 * NotchGeometry.baseWing)
        #expect(AmbientMetrics.pillExtent(four, now: now) == 0)
    }

    @Test func aWidePillGrowsSymmetricallyAndStaysCapped() {
        let wide = content([item("a", text: "Mmmmmmmmmm"), item("a2", text: "Mmmmmmmmmm")], [item("b", text: "Mmmmmmmmmm"), item("b2", text: "Mmmmmmmmmm")])
        let extent = AmbientMetrics.pillExtent(wide, now: now)
        #expect(extent > 0 && extent <= NotchGeometry.maxWingExtent)
        let huge = content([item("a", text: String(repeating: "M", count: 40))], [item("b", text: String(repeating: "M", count: 40))])
        #expect(AmbientMetrics.pillExtent(huge, now: now) <= NotchGeometry.maxWingExtent)
    }

    @Test func extentFollowsTheScreenKind() {
        let c = content([item("a", text: "Mmmmmmmmmm"), item("a2", text: "Mmmmmmmmmm")], [item("b", text: "Mmmmmmmmmm"), item("b2", text: "Mmmmmmmmmm")])
        #expect(AmbientMetrics.extent(c, notched: true, now: now) == AmbientMetrics.notchedExtent(c, now: now))
        #expect(AmbientMetrics.extent(c, notched: false, now: now) == AmbientMetrics.pillExtent(c, now: now))
    }

    // MARK: The panel measures a stand-in

    @Test func theMeasuringItemMakesNotchGeometryReportTheNeededExtent() {
        for extent in stride(from: 1.0, through: Double(NotchGeometry.maxWingExtent), by: 1) {
            let stand = AmbientMetrics.measuringItem(forExtent: CGFloat(extent))
            let measured = NotchGeometry.wingExtent(for: stand)
            // One figure space is one point: the panel is exactly as wide as asked, no padding on top.
            #expect(measured == CGFloat(extent), "extent \(extent) measured \(measured)")
        }
    }

    @Test func theClosedFrameOfAPillGrowsByTheMeasuredExtentOnBothSidesAndStaysCentered() {
        let screen = CGRect(x: 0, y: 0, width: 3440, height: 1440)
        let idle = NotchGeometry.idle(screenFrame: screen, safeAreaTop: 0, auxLeft: nil, auxRight: nil)
        let layout = ActivityLayout(leading: AmbientMetrics.measuringItem(forExtent: 40),
                                    trailing: AmbientMetrics.measuringItem(forExtent: 40), dot: nil)
        let frame = NotchGeometry.closedFrame(from: idle, layout: layout, screenFrame: screen)
        #expect(frame.width == idle.frame.width + 2 * (NotchGeometry.baseWing + 40))
        #expect(frame.midX == idle.frame.midX)
        #expect(frame.maxY == idle.frame.maxY)
    }

    @Test func aPillWithOneSidedContentStillStaysCentered() {
        let screen = CGRect(x: 0, y: 0, width: 3440, height: 1440)
        let idle = NotchGeometry.idle(screenFrame: screen, safeAreaTop: 0, auxLeft: nil, auxRight: nil)
        let layout = ActivityLayout(leading: AmbientMetrics.measuringItem(forExtent: 40), trailing: nil, dot: nil)
        let frame = NotchGeometry.closedFrame(from: idle, layout: layout, screenFrame: screen)
        #expect(frame.midX == idle.frame.midX)
        #expect(frame.width == idle.frame.width + 2 * (NotchGeometry.baseWing + 40))
    }

    // MARK: Fitting a wing

    @Test func aWingThatFitsIsLeftAlone() {
        let items = [item("a", text: "58%")]
        #expect(AmbientMetrics.fitted(items, width: 112, now: now) == items)
    }

    @Test func aTightWingDropsTheLastElementWholeInsteadOfLeavingItsBareIcon() {
        let a = item("a", text: "58%"), b = item("b", text: "82%")
        let width = AmbientMetrics.groupWidth([a, b], now: now) + 2 * AmbientMetrics.wingPadding - 1
        let out = AmbientMetrics.fitted([a, b], width: width, now: now)
        #expect(out.map(\.id) == ["a"])
        #expect(out[0].text == "58%")
    }

    @Test func aTightWingKeepsTheGlyphOfAnElementWhoseStateStandsAlone() {
        let a = AmbientIndicator(id: "claude", channel: AmbientChannel.claude, symbol: "sparkles", priority: .claudeWorking,
                                 isBusy: true, clockSince: now.addingTimeInterval(-60))
        let b = item("b", text: "82%")
        let width = AmbientMetrics.groupWidth([a, b], now: now) + 2 * AmbientMetrics.wingPadding - 1
        let out = AmbientMetrics.fitted([a, b], width: width, now: now)
        #expect(out.map(\.id) == ["claude"])
        #expect(out[0].clockSince != nil)
    }

    @Test func aVeryTightWingShowsNothingRatherThanBareIcons() {
        let items = [item("a", text: "58%"), item("b", text: "82%"), item("c", text: "99%")]
        let out = AmbientMetrics.fitted(items, width: 10, now: now)
        #expect(out.isEmpty)
    }

    @Test func fittingNothingGivesNothing() {
        #expect(AmbientMetrics.fitted([], width: 0, now: now).isEmpty)
    }
}
