import CoreGraphics
import Testing
@testable import IslandKit

/// The closed island, and the hover zone that is the same rectangle, never depend on what is shown: with
/// nothing to show it is still the base pill on a screen with no notch.
@Suite struct ClosedPillFloorTests {
    private let screen = CGRect(x: 0, y: 0, width: 3440, height: 1440)

    @Test func noNotchEmptyLayoutKeepsAVisiblePill() {
        let idle = NotchGeometry.idle(screenFrame: screen, safeAreaTop: 0, auxLeft: nil, auxRight: nil)
        let frame = NotchGeometry.closedFrame(
            from: idle, wingExtent: NotchGeometry.wingExtent(for: ActivityLayout.empty), screenFrame: screen)
        #expect(!idle.hasNotch)
        #expect(frame.width >= 190)
        #expect(frame.height >= 28)
        #expect(frame.maxY == screen.maxY)
        #expect(abs(frame.midX - screen.midX) < 0.5)
    }

    @Test func notchedEmptyLayoutKeepsTheBaseWings() {
        let idle = NotchGeometry.idle(
            screenFrame: screen, safeAreaTop: 34,
            auxLeft: CGRect(x: 0, y: 1406, width: 1627.5, height: 34),
            auxRight: CGRect(x: 1812.5, y: 1406, width: 1627.5, height: 34))
        let frame = NotchGeometry.closedFrame(from: idle, wingExtent: 0, screenFrame: screen)
        #expect(idle.hasNotch)
        #expect(frame.width == idle.frame.width + 2 * NotchGeometry.baseWing)
        #expect(frame.height == 34)
    }
}
