import CoreGraphics
import Foundation
import IslandTestSupport
import Testing
@testable import ShellKit

private final class LevelBox: @unchecked Sendable {
    var value: Double
    init(_ value: Double) { self.value = value }
}

@MainActor
@Suite struct HomeGeometryTests {
    private let band = ShellLayout.topBandHeight  // 38

    private func model(_ defaults: UserDefaults, volume: LevelBackend = LevelBackend.unsupported("x")) -> HomeModel {
        HomeModel(defaults: defaults, volume: volume, brightness: LevelBackend.unsupported("x"))
    }

    @Test func compactIsTwoRowsSpaciousThree() {
        let compact = HomeGeometry.homeBody(mode: .compact, customWidth: 440, customHeight: 480, band: band)
        let spacious = HomeGeometry.homeBody(mode: .spacious, customWidth: 440, customHeight: 480, band: band)
        #expect(compact == CGSize(width: 440, height: 290))
        #expect(spacious == CGSize(width: 532, height: 354))
    }

    @Test func customRowsFollowTheMaximumHeight() {
        func rows(_ h: Double) -> Int { HomeGeometry.tileRows(for: .custom, customHeight: h, band: band) }
        #expect(rows(260) == 1)
        #expect(rows(289) == 1)
        #expect(rows(290) == 2)
        #expect(rows(480) == 4)
        #expect(rows(640) == 6)
        for h in stride(from: 260.0, through: 640.0, by: 10) {
            let body = HomeGeometry.homeBody(mode: .custom, customWidth: 440, customHeight: h, band: band)
            #expect(body.height <= CGFloat(h))
        }
    }

    @Test func customWidthIsClamped() {
        #expect(HomeGeometry.homeBody(mode: .custom, customWidth: 100, customHeight: 480, band: band).width == 360)
        #expect(HomeGeometry.homeBody(mode: .custom, customWidth: 900, customHeight: 480, band: band).width == 600)
        #expect(HomeGeometry.homeBody(mode: .custom, customWidth: 500, customHeight: 480, band: band).width == 500)
    }

    @Test func aTallerBandGrowsTheBody() {
        let a = HomeGeometry.homeBody(mode: .spacious, customWidth: 440, customHeight: 480, band: 38)
        let b = HomeGeometry.homeBody(mode: .spacious, customWidth: 440, customHeight: 480, band: 42)
        #expect(b.height - a.height == 4)
    }

    @Test func panelAddsRoomOnlyWhereButtonsExist() {
        let body = CGSize(width: 532, height: 354)
        #expect(HomeGeometry.panel(body: body, sideButtons: true, bottomButtons: true) == CGSize(width: 660, height: 416))
        #expect(HomeGeometry.panel(body: body, sideButtons: false, bottomButtons: true) == CGSize(width: 532, height: 416))
        #expect(HomeGeometry.panel(body: body, sideButtons: false, bottomButtons: false) == body)
    }

    @Test func exploreKeepsHomeWidthAndFitsRows() {
        let home = CGSize(width: 532, height: 354)
        func explore(_ count: Int) -> CGSize { HomeGeometry.exploreBody(home: home, itemCount: count, columns: 5, band: band) }
        #expect(explore(9).width == 532 && explore(13).width == 532)
        #expect(explore(11).height - explore(10).height == HomeGeometry.tileRow)  // 10 tiles = 2 rows, 11 = 3
        #expect(explore(10).height - explore(0).height == HomeGeometry.tileRow)
        // Four rows at most: more tiles scroll instead of growing the island.
        #expect(explore(20) == explore(60))
        #expect(explore(20).height - explore(0).height == 3 * HomeGeometry.tileRow)
    }

    @Test func modelMapsEachSizeModeToItsPanel() {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        let m = model(bench.defaults)
        #expect(m.sizeMode == IslandSizeMode.spacious && m.homeBody.height == 354)
        m.sizeMode = IslandSizeMode.compact
        #expect(m.homeBody.height == 290)
        m.sizeMode = IslandSizeMode.custom
        m.customWidth = 560
        m.customHeight = 640
        #expect(m.homeBody == CGSize(width: 560, height: 546))
        #expect(m.tileColumns == 5 && m.tileRows(tileCount: 40) == 6)
        #expect(m.panelSize(body: m.homeBody) == CGSize(width: 688, height: 608))
    }

    @Test func sizeAndLookPersistClamped() {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        let m = model(bench.defaults)
        m.sizeMode = IslandSizeMode.custom
        m.customWidth = 9_999
        m.translucentBackground = true
        m.showsOutline = true
        m.notchFitWidth = 50
        m.notchFitHeight = -50
        m.hidesNotchGap = true
        #expect(m.customWidth == 600 && m.notchFitWidth == 10 && m.notchFitHeight == -6)
        let again = model(bench.defaults)
        #expect(again.sizeMode == IslandSizeMode.custom && again.customWidth == 600)
        #expect(again.translucentBackground && again.showsOutline && again.hidesNotchGap)
        #expect(again.bandHeight == 38 - 6 + HomeModel.hiddenGapExtra)
    }

    @Test func garbageDefaultsFallBack() {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        bench.defaults.set("giant", forKey: HomeModel.Keys.size)
        bench.defaults.set("wide", forKey: HomeModel.Keys.customWidth)
        bench.defaults.set(Double.nan, forKey: HomeModel.Keys.fitWidth)
        let m = model(bench.defaults)
        #expect(m.sizeMode == IslandSizeMode.spacious && m.customWidth == 440 && m.notchFitWidth == 0)
    }

    @Test func unsupportedSliderDoesNotPretend() {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        let m = model(bench.defaults, volume: LevelBackend.unsupported("pas de sortie"))
        m.volume.set(0.5)
        #expect(!m.volume.isAvailable && m.volume.value == 0)
        #expect(m.volume.unavailableReason == "pas de sortie")
    }

    @Test func workingSliderWritesThroughAndFollowsSystem() {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        let box = LevelBox(0.25)
        let backend = LevelBackend(read: { box.value }, write: { box.value = $0; return true }, unavailableReason: "x")
        let m = model(bench.defaults, volume: backend)
        #expect(m.volume.isAvailable && m.volume.value == 0.25)
        m.volume.set(1.7)
        #expect(box.value == 1 && m.volume.value == 1)
        box.value = 0.4
        m.refreshLevels()
        #expect(m.volume.value == 0.4)
    }
}
