import CoreGraphics
import Testing
@testable import IslandKit

@Suite struct NotchGeometryTests {
    // MacBook Pro 14": 1512x982 points, 32 pt safe-area inset, notch about 184 pt wide.
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func notchScreenUsesTheGapBetweenTheTwoAuxiliaryAreas() {
        let left = CGRect(x: 0, y: 950, width: 664, height: 32)
        let right = CGRect(x: 848, y: 950, width: 664, height: 32)
        let g = NotchGeometry.idle(screenFrame: screen, safeAreaTop: 32,
                                   auxLeft: left, auxRight: right)
        #expect(g.hasNotch)
        #expect(g.frame.width == 184)
        #expect(g.frame.height == 32)
        #expect(g.frame.midX == screen.midX)
        #expect(g.frame.maxY == screen.maxY, "flush with the top edge")
    }

    @Test func screenWithoutNotchGetsABlackPillAtTopCenter() {
        let g = NotchGeometry.idle(screenFrame: screen, safeAreaTop: 0, auxLeft: nil, auxRight: nil)
        #expect(!g.hasNotch)
        #expect(g.frame.width == NotchGeometry.pillWidth)
        #expect(g.frame.height == NotchGeometry.pillHeight)
        #expect(g.frame.midX == screen.midX)
        #expect(g.frame.maxY == screen.maxY)
    }

    @Test func expandedPanelKeepsTheTopCenterAnchor() {
        let idle = NotchGeometry.idle(screenFrame: screen, safeAreaTop: 0, auxLeft: nil, auxRight: nil)
        let open = NotchGeometry.expanded(from: idle, size: CGSize(width: 640, height: 360), screenFrame: screen)
        #expect(open.width == 640)
        #expect(open.height == 360)
        #expect(open.midX == idle.frame.midX)
        #expect(open.maxY == screen.maxY)
    }

    @Test func expandedPanelNeverLeavesTheScreen() {
        let idle = NotchGeometry.idle(screenFrame: screen, safeAreaTop: 0, auxLeft: nil, auxRight: nil)
        let open = NotchGeometry.expanded(from: idle, size: CGSize(width: 4000, height: 4000), screenFrame: screen)
        #expect(open.width <= screen.width)
        #expect(open.height <= screen.height)
        #expect(screen.contains(open))
    }

    @Test func offsetScreenOriginIsRespected() {
        let second = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let g = NotchGeometry.idle(screenFrame: second, safeAreaTop: 0, auxLeft: nil, auxRight: nil)
        #expect(g.frame.midX == second.midX)
        #expect(g.frame.maxY == second.maxY)
    }
}
