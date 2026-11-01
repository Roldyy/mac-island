import CoreGraphics
import Foundation
import IslandUI
import Testing
@testable import IslandKit

/// Pure widths of the closed island for a given set of visible indicators: the notch plus only the wings the
/// indicators strictly need, nothing reserved for an absent item. Notch 184 pt (a hardware notch) and a screen
/// without a notch (the 200 pt pill).
@Suite struct ClosedWidthConfigurationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let notch: CGFloat = 184
    private let screen = CGRect(x: 0, y: 0, width: 3440, height: 1440)

    private var claude: AmbientIndicator {
        AmbientIndicator(id: "claude", channel: AmbientChannel.claude, symbol: "sparkles", wing: .leading)
    }
    private var clock: AmbientIndicator {
        AmbientIndicator(id: "clock", channel: AmbientChannel.clock, symbol: "clock", text: "12:34", wing: .leading)
    }
    private var battery: AmbientIndicator {
        AmbientIndicator(id: "battery", channel: AmbientChannel.battery, symbol: "battery.75percent", text: "82%", wing: .trailing)
    }
    private var cup: AmbientIndicator {
        AmbientIndicator(id: "keepAwake", channel: AmbientChannel.keepAwake, symbol: "cup.and.saucer.fill", wing: .trailing)
    }

    private var notchIdle: NotchGeometry {
        NotchGeometry.idle(
            screenFrame: screen, safeAreaTop: 34,
            auxLeft: CGRect(x: 0, y: 1406, width: (screen.width - notch) / 2, height: 34),
            auxRight: CGRect(x: (screen.width + notch) / 2, y: 1406, width: (screen.width - notch) / 2, height: 34))
    }

    /// Wing width of a side as the panel gets it: the width proxy's stand-in item, measured by the geometry.
    private func wing(_ extent: CGFloat) -> CGFloat {
        extent > 0 ? NotchGeometry.baseWing + NotchGeometry.wingExtent(for: AmbientMetrics.measuringItem(forExtent: extent)) : 0
    }

    private func notchedFrame(_ content: ClosedIslandContent) -> CGRect {
        let extents = AmbientMetrics.notchedExtents(content, now: now)
        return NotchGeometry.closedFrame(
            from: notchIdle, leading: wing(extents.leading), trailing: wing(extents.trailing), screenFrame: screen)
    }

    private func notchedWidth(_ content: ClosedIslandContent) -> CGFloat { notchedFrame(content).width }

    private func flatWidth(_ content: ClosedIslandContent) -> CGFloat {
        let idle = NotchGeometry.idle(screenFrame: screen, safeAreaTop: 0, auxLeft: nil, auxRight: nil)
        let extent = AmbientMetrics.pillExtent(content, now: now)
        return NotchGeometry.closedFrame(from: idle, leading: wing(extent), trailing: wing(extent), screenFrame: screen).width
    }

    // MARK: Notch 184

    @Test func nothingVisibleIsExactlyTheNotch() {
        let frame = notchedFrame(.empty)
        #expect(frame.width == notch)
        #expect(frame.minX == notchIdle.frame.minX)
        print("closed-width notch 184 nothing: \(frame.width)")
    }

    @Test func eachSideTakesOnlyWhatItsOwnItemsNeed() {
        let both = ClosedIslandContent(leading: [claude, clock], trailing: [battery, cup])
        let leftOnly = ClosedIslandContent(leading: [claude, clock], trailing: [])
        let rightOnly = ClosedIslandContent(leading: [], trailing: [battery, cup])
        let l = AmbientMetrics.groupWidth(both.leading, now: now) + 2 * AmbientMetrics.wingPadding
        let r = AmbientMetrics.groupWidth(both.trailing, now: now) + 2 * AmbientMetrics.wingPadding
        let frame = notchedFrame(both)
        let idle = notchIdle.frame
        // Each side is its own content (rounded up to a point), the notch is untouched in the middle.
        #expect(idle.minX - frame.minX >= min(l, 67) && idle.minX - frame.minX <= min(l, 67) + 1)
        #expect(frame.maxX - idle.maxX >= min(r, 67) && frame.maxX - idle.maxX <= min(r, 67) + 1)
        // A side with nothing has no wing at all.
        let left = notchedFrame(leftOnly)
        #expect(left.maxX == idle.maxX && left.minX == frame.minX)
        let right = notchedFrame(rightOnly)
        #expect(right.minX == idle.minX && right.maxX == frame.maxX)
        #expect(left.width + right.width == frame.width + notch)
        print("closed-width notch 184 claude + clock | battery + cup: \(frame.width) (left \(idle.minX - frame.minX), right \(frame.maxX - idle.maxX))")
    }

    @Test func aSingleSidedIslandIsNotChattierThanItsContent() {
        let clockOnly = notchedFrame(ClosedIslandContent(leading: [clock], trailing: []))
        #expect(clockOnly.maxX == notchIdle.frame.maxX)
        #expect(clockOnly.width < notch + 2 * NotchGeometry.baseWing + AmbientMetrics.groupWidth([clock], now: now) + 2 * AmbientMetrics.wingPadding)
        let batteryOnly = notchedFrame(ClosedIslandContent(leading: [], trailing: [battery]))
        #expect(batteryOnly.minX == notchIdle.frame.minX)
        #expect(batteryOnly.width > notch)
    }

    @Test func aWingNeverReservesMoreThanItsContent() {
        let sets: [(String, ClosedIslandContent)] = [
            ("clock only", ClosedIslandContent(leading: [clock], trailing: [])),
            ("battery only", ClosedIslandContent(leading: [], trailing: [battery])),
            ("cup only", ClosedIslandContent(leading: [], trailing: [cup])),
            ("clock + battery", ClosedIslandContent(leading: [clock], trailing: [battery])),
            ("claude + clock | battery + cup", ClosedIslandContent(leading: [claude, clock], trailing: [battery, cup])),
        ]
        for (name, content) in sets {
            let width = notchedWidth(content)
            // Exactly each group plus its two paddings, on its own side of the notch (rounded up to a point).
            func side(_ items: [AmbientIndicator]) -> CGFloat {
                let need = AmbientMetrics.groupWidth(items, now: now)
                return need > 0 ? min(NotchGeometry.baseWing + NotchGeometry.maxWingExtent, need + 2 * AmbientMetrics.wingPadding) : 0
            }
            let wings = side(content.leading) + side(content.trailing)
            #expect(width >= notch + wings, "\(name): \(width)")
            #expect(width <= notch + wings + 2, "\(name): \(width)")
            #expect(width >= notch)
            print("closed-width notch 184 \(name): \(width)")
        }
    }

    @Test func aBiggerSetIsNeverNarrowerThanASmallerOne() {
        let small = notchedWidth(ClosedIslandContent(leading: [clock], trailing: []))
        let mid = notchedWidth(ClosedIslandContent(leading: [clock], trailing: [battery]))
        let full = notchedWidth(ClosedIslandContent(leading: [claude, clock], trailing: [battery, cup]))
        #expect(notchedWidth(.empty) <= small)
        #expect(small <= mid)
        #expect(mid <= full)
    }

    @Test func theFourDefaultItemsStayWithinTheLongestWing() {
        let full = notchedWidth(ClosedIslandContent(leading: [claude, clock], trailing: [battery, cup]))
        #expect(full <= notch + 2 * (NotchGeometry.baseWing + NotchGeometry.maxWingExtent))
    }

    @Test func aDotAloneAddsOnlyASmallWing() {
        let width = notchedWidth(ClosedIslandContent(leading: [], trailing: [], dot: .warning))
        // One small wing, on the right where the dot is drawn.
        #expect(width == notch + NotchGeometry.baseWing + AmbientMetrics.dotExtent)
        let frame = notchedFrame(ClosedIslandContent(leading: [], trailing: [], dot: .warning))
        #expect(frame.minX == notchIdle.frame.minX)
    }

    // MARK: No notch

    @Test func withoutANotchTheEmptyPillIsThePillPlusARim() {
        let width = flatWidth(.empty)
        #expect(width == NotchGeometry.pillWidth + 2 * NotchGeometry.baseWing)
        #expect(width >= NotchGeometry.pillWidth)
        print("closed-width flat nothing: \(width)")
    }

    @Test func withoutANotchTheItemsShareThePillBeforeAnyGrowth() {
        let content = ClosedIslandContent(leading: [claude], trailing: [battery, cup], center: clock)
        let width = flatWidth(content)
        #expect(width >= NotchGeometry.pillWidth + 2 * NotchGeometry.baseWing)
        #expect(width <= NotchGeometry.pillWidth + 2 * (NotchGeometry.baseWing + NotchGeometry.maxWingExtent))
        print("closed-width flat claude | clock | battery + cup: \(width)")
    }

    @Test func aOneSidedFlatPillGrowsSymmetricallyAroundTheClock() {
        let left = ClosedIslandContent(leading: [claude, cup], trailing: [], center: clock)
        let right = ClosedIslandContent(leading: [], trailing: [claude, cup], center: clock)
        #expect(flatWidth(left) == flatWidth(right))
    }
}
