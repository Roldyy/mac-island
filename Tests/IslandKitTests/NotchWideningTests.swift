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

    @Test func emptyLayoutIsExactlyTheNotch() {
        let frame = NotchGeometry.closedFrame(from: notch, layout: .empty, screenFrame: screen)
        #expect(frame == notch.frame)
        #expect(frame.midX == notch.frame.midX)
        #expect(frame.height == notch.frame.height)
        #expect(frame.maxY == screen.maxY)
    }

    @Test func aDotAloneDoesNotWiden() {
        let layout = ActivityLayout(leading: nil, trailing: nil, dot: .danger)
        #expect(NotchGeometry.wingExtent(for: layout) == 0)
    }

    @Test func aLeftOnlyWingWidensTheLeftSideAndTheNotchStaysPut() {
        let layout = ActivityLayout(
            leading: CompactItem(symbol: "sparkles", text: "Attend"), trailing: nil, dot: nil)
        let wing = NotchGeometry.baseWing + NotchGeometry.wingExtent(for: layout.leading)
        let frame = NotchGeometry.closedFrame(from: notch, layout: layout, screenFrame: screen)
        #expect(frame.width == notch.frame.width + wing)
        #expect(frame.minX == notch.frame.minX - wing)
        #expect(frame.maxX == notch.frame.maxX)
    }

    @Test func aRightOnlyWingWidensTheRightSideAndTheNotchStaysPut() {
        let layout = ActivityLayout(leading: nil, trailing: CompactItem(symbol: "x", text: "82%"), dot: nil)
        let wing = NotchGeometry.baseWing + NotchGeometry.wingExtent(for: layout.trailing)
        let frame = NotchGeometry.closedFrame(from: notch, layout: layout, screenFrame: screen)
        #expect(frame.minX == notch.frame.minX)
        #expect(frame.maxX == notch.frame.maxX + wing)
        #expect(frame.width == notch.frame.width + wing)
    }

    @Test func eachSideTakesOnlyItsOwnWidthAndTheOriginFollowsTheLeftWing() {
        let a = CompactItem(symbol: "x", text: "a")
        let b = CompactItem(symbol: "x", text: "abcdefgh")
        let layout = ActivityLayout(leading: a, trailing: b, dot: nil)
        let wings = NotchGeometry.wingWidths(for: layout)
        #expect(wings.leading == NotchGeometry.baseWing + NotchGeometry.wingExtent(for: a))
        #expect(wings.trailing == NotchGeometry.baseWing + NotchGeometry.wingExtent(for: b))
        #expect(wings.leading < wings.trailing)
        let frame = NotchGeometry.closedFrame(from: notch, layout: layout, screenFrame: screen)
        #expect(frame.width == notch.frame.width + wings.leading + wings.trailing)
        // x origin = notch centre - notch / 2 - left wing.
        #expect(frame.minX == notch.frame.midX - notch.frame.width / 2 - wings.leading)
        // The notch is where the hardware is, so the frame itself is off-centre by half the difference.
        #expect(frame.midX == notch.frame.midX + (wings.trailing - wings.leading) / 2)
        #expect(frame.minX <= notch.frame.minX && frame.maxX >= notch.frame.maxX)
    }

    @Test func aDotAloneSitsOnASmallRightWing() {
        let layout = ActivityLayout(leading: nil, trailing: nil, dot: .danger)
        let wings = NotchGeometry.wingWidths(for: layout)
        #expect(wings.leading == 0 && wings.trailing == NotchGeometry.baseWing)
    }

    @Test func longTextIsCapped() {
        let long = CompactItem(symbol: "x", text: String(repeating: "W", count: 200))
        #expect(NotchGeometry.wingExtent(for: long) == NotchGeometry.maxWingExtent)
        let frame = NotchGeometry.closedFrame(from: notch, leading: 10_000, trailing: 10_000, screenFrame: screen)
        #expect(frame.width == notch.frame.width + 2 * (NotchGeometry.baseWing + NotchGeometry.maxWingExtent))
    }

    @Test func extentGrowsWithTextButNeverShrinksBelowTheGlyph() {
        let none = NotchGeometry.wingExtent(for: CompactItem(symbol: "x"))
        let short = NotchGeometry.wingExtent(for: CompactItem(symbol: "x", text: "ab"))
        let longer = NotchGeometry.wingExtent(for: CompactItem(symbol: "x", text: "abcdef"))
        #expect(0 < none && none < short && short < longer)
        #expect(NotchGeometry.wingExtent(for: nil as CompactItem?) == 0)
    }

    @Test func theLargestSideIsTheLayoutExtent() {
        let a = CompactItem(symbol: "x", text: "a")
        let b = CompactItem(symbol: "x", text: "abcdefgh")
        let layout = ActivityLayout(leading: a, trailing: b, dot: nil)
        #expect(NotchGeometry.wingExtent(for: layout) == NotchGeometry.wingExtent(for: b))
    }

    @Test func aLopsidedFrameOnAnEdgeNotchIsKeptOnScreen() {
        let edge = CGRect(x: 0, y: 0, width: 400, height: 300)
        let idle = NotchGeometry.idle(
            screenFrame: edge, safeAreaTop: 32,
            auxLeft: CGRect(x: 0, y: 268, width: 20, height: 32),
            auxRight: CGRect(x: 120, y: 268, width: 280, height: 32))
        let frame = NotchGeometry.closedFrame(from: idle, leading: 67, trailing: 10, screenFrame: edge)
        #expect(frame.minX >= edge.minX && frame.maxX <= edge.maxX)
    }

    @Test func closedFrameNeverLeavesAnEdgeToEdgeScreen() {
        let tiny = CGRect(x: 100, y: 0, width: 220, height: 600)
        let idle = NotchGeometry.idle(screenFrame: tiny, safeAreaTop: 0, auxLeft: nil, auxRight: nil)
        let frame = NotchGeometry.closedFrame(from: idle, leading: 99, trailing: 99, screenFrame: tiny)
        #expect(frame.width <= tiny.width)
        #expect(frame.minX >= tiny.minX && frame.maxX <= tiny.maxX)
    }

    @Test func theRevealShapeStartsOnTheClosedIslandAndEndsCentered() {
        let rect = CGRect(x: 0, y: 0, width: 640, height: 300)
        // Closed island 20 pt right of the centre: its left edge sits there at progress 0, the open shape is centred.
        let start = IslandRevealShape.originX(progress: 0, width: 200, in: rect, closedOffset: 20)
        #expect(start == rect.midX - 100 + 20)
        let end = IslandRevealShape.originX(progress: 1, width: 640, in: rect, closedOffset: 20)
        #expect(end == rect.midX - 320)
        let path = IslandRevealShape(progress: 0, closedSize: CGSize(width: 200, height: 32), closedOffset: 20).path(in: rect)
        #expect(path.boundingRect.midX.rounded() == (rect.midX + 20).rounded())
    }

    @Test func openHeightIsClampedToUsableRange() {
        #expect(NotchGeometry.clampedOpenHeight(50, screenFrame: screen) == NotchGeometry.minOpenHeight)
        #expect(NotchGeometry.clampedOpenHeight(420, screenFrame: screen) == 420)
        #expect(NotchGeometry.clampedOpenHeight(5000, screenFrame: screen) == screen.height)
        let short = CGRect(x: 0, y: 0, width: 800, height: 90)
        #expect(NotchGeometry.clampedOpenHeight(300, screenFrame: short) == 90)
    }
}
