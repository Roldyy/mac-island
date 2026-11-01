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

    private func notchedWidth(_ content: ClosedIslandContent) -> CGFloat {
        let idle = NotchGeometry.idle(
            screenFrame: screen, safeAreaTop: 34,
            auxLeft: CGRect(x: 0, y: 1406, width: (screen.width - notch) / 2, height: 34),
            auxRight: CGRect(x: (screen.width + notch) / 2, y: 1406, width: (screen.width - notch) / 2, height: 34))
        let extent = AmbientMetrics.notchedExtent(content, now: now)
        return NotchGeometry.closedFrame(from: idle, wingExtent: extent, screenFrame: screen).width
    }

    private func flatWidth(_ content: ClosedIslandContent) -> CGFloat {
        let idle = NotchGeometry.idle(screenFrame: screen, safeAreaTop: 0, auxLeft: nil, auxRight: nil)
        let extent = AmbientMetrics.pillExtent(content, now: now)
        return NotchGeometry.closedFrame(from: idle, wingExtent: extent, screenFrame: screen).width
    }

    // MARK: Notch 184

    @Test func nothingVisibleIsTheNotchPlusARim() {
        let width = notchedWidth(.empty)
        #expect(width == notch + 2 * NotchGeometry.baseWing)
        #expect(width >= notch)
        #expect(width <= notch + 8)
        print("closed-width notch 184 nothing: \(width)")
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
            let need = max(AmbientMetrics.groupWidth(content.leading, now: now),
                           AmbientMetrics.groupWidth(content.trailing, now: now))
            // Exactly the widest group plus its two paddings, on each side of the notch (rounded up to a point).
            let wing = min(NotchGeometry.baseWing + NotchGeometry.maxWingExtent, max(NotchGeometry.baseWing, need + 2 * AmbientMetrics.wingPadding))
            #expect(width >= notch + 2 * wing, "\(name): \(width)")
            #expect(width <= notch + 2 * wing + 2, "\(name): \(width)")
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
        #expect(width == notch + 2 * (NotchGeometry.baseWing + AmbientMetrics.dotExtent))
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
