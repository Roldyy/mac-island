import CoreGraphics
import Testing
import IslandUI
@testable import IslandKit

@Suite struct NotchWideningTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private var notch: NotchGeometry {
        NotchGeometry.idle(
            screenFrame: screen, safeAreaTop: 32,
            auxLeft: CGRect(x: 0, y: 950, width: 664, height: 32),
            auxRight: CGRect(x: 848, y: 950, width: 664, height: 32))
    }

    @Test func emptyLayoutKeepsTheRestingPill() {
        let frame = NotchGeometry.closedFrame(
            from: notch, wingExtent: NotchGeometry.wingExtent(for: .empty), screenFrame: screen)
        #expect(frame.width == notch.frame.width + 2 * NotchGeometry.baseWing)
        #expect(frame.midX == notch.frame.midX)
        #expect(frame.height == notch.frame.height)
        #expect(frame.maxY == screen.maxY)
    }

    @Test func aDotAloneDoesNotWiden() {
        let layout = ActivityLayout(leading: nil, trailing: nil, dot: .danger)
        #expect(NotchGeometry.wingExtent(for: layout) == 0)
    }

    @Test func aWingWidensBothSidesSoTheNotchStaysCentered() {
        let layout = ActivityLayout(
            leading: CompactItem(symbol: "sparkles", text: "Attend"), trailing: nil, dot: nil)
        let extent = NotchGeometry.wingExtent(for: layout)
        #expect(extent > 0)
        let frame = NotchGeometry.closedFrame(from: notch, wingExtent: extent, screenFrame: screen)
        #expect(frame.width == notch.frame.width + 2 * (NotchGeometry.baseWing + extent))
        #expect(frame.midX == notch.frame.midX)
    }

    @Test func longTextIsCapped() {
        let long = CompactItem(symbol: "x", text: String(repeating: "W", count: 200))
        #expect(NotchGeometry.wingExtent(for: long) == NotchGeometry.maxWingExtent)
        let frame = NotchGeometry.closedFrame(from: notch, wingExtent: 10_000, screenFrame: screen)
        #expect(frame.width == notch.frame.width + 2 * (NotchGeometry.baseWing + NotchGeometry.maxWingExtent))
    }

    @Test func extentGrowsWithTextButNeverShrinksBelowTheGlyph() {
        let none = NotchGeometry.wingExtent(for: CompactItem(symbol: "x"))
        let short = NotchGeometry.wingExtent(for: CompactItem(symbol: "x", text: "ab"))
        let longer = NotchGeometry.wingExtent(for: CompactItem(symbol: "x", text: "abcdef"))
        #expect(0 < none && none < short && short < longer)
        #expect(NotchGeometry.wingExtent(for: nil as CompactItem?) == 0)
    }

    @Test func largerWingWinsTheSharedExtent() {
        let a = CompactItem(symbol: "x", text: "a")
        let b = CompactItem(symbol: "x", text: "abcdefgh")
        let layout = ActivityLayout(leading: a, trailing: b, dot: nil)
        #expect(NotchGeometry.wingExtent(for: layout) == NotchGeometry.wingExtent(for: b))
    }

    @Test func closedFrameNeverLeavesAnEdgeToEdgeScreen() {
        let tiny = CGRect(x: 100, y: 0, width: 220, height: 600)
        let idle = NotchGeometry.idle(screenFrame: tiny, safeAreaTop: 0, auxLeft: nil, auxRight: nil)
        let frame = NotchGeometry.closedFrame(from: idle, wingExtent: 96, screenFrame: tiny)
        #expect(frame.width <= tiny.width)
        #expect(frame.minX >= tiny.minX && frame.maxX <= tiny.maxX)
    }

    @Test func openHeightIsClampedToUsableRange() {
        #expect(NotchGeometry.clampedOpenHeight(50, screenFrame: screen) == NotchGeometry.minOpenHeight)
        #expect(NotchGeometry.clampedOpenHeight(420, screenFrame: screen) == 420)
        #expect(NotchGeometry.clampedOpenHeight(5000, screenFrame: screen) == screen.height)
        let short = CGRect(x: 0, y: 0, width: 800, height: 90)
        #expect(NotchGeometry.clampedOpenHeight(300, screenFrame: short) == 90)
    }
}
