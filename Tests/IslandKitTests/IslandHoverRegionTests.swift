import CoreGraphics
import Testing
@testable import IslandKit

/// The hover zone is the closed island (notch plus wings) while closed and the whole panel while open, plus the
/// two points above the top edge where the pointer stops. The tracking rect is that zone seen from the panel.
@Suite struct IslandHoverRegionTests {
    private let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let notch = NotchGeometry.idle(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
        auxLeft: CGRect(x: 0, y: 950, width: 664, height: 32), auxRight: CGRect(x: 848, y: 950, width: 664, height: 32))

    @Test func closedZoneCoversTheNotchAndBothWings() {
        let closed = NotchGeometry.closedFrame(from: notch, leading: 60, trailing: 40, screenFrame: main)
        let zone = IslandHoverRegion.zone(closedFrame: closed, panelFrame: closed, isOpen: false)
        #expect(zone.minX == notch.frame.minX - 60)
        #expect(zone.maxX == notch.frame.maxX + 40)
        #expect(zone.contains(CGPoint(x: notch.frame.midX, y: 981)), "on the notch")
        #expect(zone.contains(CGPoint(x: notch.frame.minX - 59, y: 960)), "on the leading wing")
        #expect(zone.contains(CGPoint(x: notch.frame.maxX + 39, y: 960)), "on the trailing wing")
        #expect(!zone.contains(CGPoint(x: notch.frame.minX - 61, y: 960)))
        #expect(!zone.contains(CGPoint(x: notch.frame.midX, y: 940)), "below the strip")
        #expect(notch.frame.width == 184)
    }

    @Test func pointerStoppedAtTheTopEdgeStillCounts() {
        let closed = NotchGeometry.closedFrame(from: notch, leading: 0, trailing: 0, screenFrame: main)
        let zone = IslandHoverRegion.zone(closedFrame: closed, panelFrame: closed, isOpen: false)
        #expect(zone.contains(CGPoint(x: notch.frame.midX, y: main.maxY)))
    }

    @Test func noNotchScreenUsesItsCentredPill() {
        let idle = NotchGeometry.idle(screenFrame: main, safeAreaTop: 0, auxLeft: nil, auxRight: nil)
        let closed = NotchGeometry.closedFrame(from: idle, leading: 0, trailing: 0, screenFrame: main)
        let zone = IslandHoverRegion.zone(closedFrame: closed, panelFrame: closed, isOpen: false)
        #expect(zone.midX == main.midX)
        #expect(zone.width == closed.width)
        #expect(zone.maxY == main.maxY + IslandHoverRegion.topReach)
    }

    @Test func openZoneIsTheWholePanel() {
        let closed = NotchGeometry.closedFrame(from: notch, leading: 60, trailing: 40, screenFrame: main)
        let open = NotchGeometry.expanded(from: notch, size: CGSize(width: 640, height: 360), screenFrame: main)
        let zone = IslandHoverRegion.zone(closedFrame: closed, panelFrame: open, isOpen: true)
        #expect(zone.minX == open.minX && zone.maxX == open.maxX && zone.minY == open.minY)
    }

    @Test func secondDisplayKeepsItsOwnOrigin() {
        // A display to the right and slightly lower than the main one.
        let second = CGRect(x: 1512, y: -120, width: 1920, height: 1080)
        let idle = NotchGeometry.idle(screenFrame: second, safeAreaTop: 0, auxLeft: nil, auxRight: nil)
        let closed = NotchGeometry.closedFrame(from: idle, leading: 0, trailing: 0, screenFrame: second)
        let zone = IslandHoverRegion.zone(closedFrame: closed, panelFrame: closed, isOpen: false)
        #expect(zone.contains(CGPoint(x: second.midX, y: second.maxY - 1)))
        #expect(!zone.contains(CGPoint(x: main.midX, y: main.maxY - 1)), "the main display's notch is not this zone")
    }

    @Test func trackingRectIsTheZoneInPanelCoordinatesClippedToThePanel() {
        let closed = NotchGeometry.closedFrame(from: notch, leading: 60, trailing: 40, screenFrame: main)
        // While the panel is still its larger union frame (closing), the zone is the small closed one inside it.
        let panel = CGRect(x: 436, y: 622, width: 640, height: 360)
        let zone = IslandHoverRegion.zone(closedFrame: closed, panelFrame: panel, isOpen: false)
        let rect = IslandHoverRegion.trackingRect(zone: zone, panelFrame: panel)
        #expect(rect.minX == closed.minX - panel.minX)
        #expect(rect.width == closed.width)
        #expect(rect.maxY == panel.height, "the two points above the screen are cut off")
        #expect(IslandHoverRegion.trackingRect(zone: CGRect(x: 5000, y: 0, width: 10, height: 10), panelFrame: panel).isEmpty)
    }
}
