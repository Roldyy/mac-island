import CoreGraphics
import Testing
@testable import DockFeature

@Suite struct PreviewGeometryTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func bottomDockEdgeAndBand() {
        let visible = CGRect(x: 0, y: 70, width: 1440, height: 800)
        #expect(DockGeometry.edge(screenFrame: screen, visibleFrame: visible) == .bottom)
        #expect(DockGeometry.band(screenFrame: screen, visibleFrame: visible) == CGRect(x: 0, y: 0, width: 1440, height: 70))
    }
    @Test func leftAndRightEdges() {
        #expect(DockGeometry.edge(screenFrame: screen, visibleFrame: CGRect(x: 60, y: 0, width: 1380, height: 870)) == .left)
        #expect(DockGeometry.edge(screenFrame: screen, visibleFrame: CGRect(x: 0, y: 0, width: 1380, height: 870)) == .right)
    }
    @Test func hiddenDockHasNoEdgeNorBand() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 870) // only the menu bar is reserved
        #expect(DockGeometry.edge(screenFrame: screen, visibleFrame: visible) == nil)
        #expect(DockGeometry.band(screenFrame: screen, visibleFrame: visible) == nil)
    }
    @Test func panelSitsAboveABottomIconCentred() {
        let icon = CGRect(x: 700, y: 4, width: 56, height: 56)
        let f = DockGeometry.previewFrame(icon: icon, size: CGSize(width: 300, height: 140), edge: .bottom, screenFrame: screen, gap: 8)
        #expect(f == CGRect(x: 578, y: 68, width: 300, height: 140))
    }
    @Test func panelIsClampedToTheScreen() {
        let icon = CGRect(x: 4, y: 4, width: 56, height: 56)
        let f = DockGeometry.previewFrame(icon: icon, size: CGSize(width: 300, height: 140), edge: .bottom, screenFrame: screen, gap: 8)
        #expect(f.minX == 0)
        let r = CGRect(x: 1400, y: 4, width: 56, height: 56)
        #expect(DockGeometry.previewFrame(icon: r, size: CGSize(width: 300, height: 140), edge: .bottom, screenFrame: screen, gap: 8).maxX == 1440)
    }
    @Test func sideDocksPlacePanelBesideTheIcon() {
        let left = CGRect(x: 4, y: 400, width: 56, height: 56)
        let fl = DockGeometry.previewFrame(icon: left, size: CGSize(width: 200, height: 100), edge: .left, screenFrame: screen, gap: 8)
        #expect(fl == CGRect(x: 68, y: 378, width: 200, height: 100))
        let right = CGRect(x: 1380, y: 400, width: 56, height: 56)
        let fr = DockGeometry.previewFrame(icon: right, size: CGSize(width: 200, height: 100), edge: .right, screenFrame: screen, gap: 8)
        #expect(fr == CGRect(x: 1172, y: 378, width: 200, height: 100))
    }
    @Test func oversizedPanelStillFitsHorizontally() {
        let f = DockGeometry.previewFrame(icon: CGRect(x: 700, y: 4, width: 56, height: 56), size: CGSize(width: 2000, height: 100),
                                          edge: .bottom, screenFrame: screen, gap: 8)
        #expect(f.minX == 0)
    }
}
