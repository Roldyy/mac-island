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

    @Test func compactIsOneRowSpaciousTwo() {
        let compact = HomeGeometry.homeBody(mode: .compact, customWidth: 440, customHeight: 480, band: band)
        let spacious = HomeGeometry.homeBody(mode: .spacious, customWidth: 440, customHeight: 480, band: band)
        #expect(compact == CGSize(width: 440, height: 238))
        #expect(spacious == CGSize(width: 532, height: 314))
    }

    @Test func customRowsFollowTheMaximumHeight() {
        func rows(_ h: Double) -> Int { HomeGeometry.tileRows(for: .custom, customHeight: h, band: band) }
        #expect(rows(260) == 1)
        #expect(rows(300) == 1)
        #expect(rows(314) == 2)
        #expect(rows(640) == 3)
        for h in stride(from: 260.0, through: 640.0, by: 10) {
            let body = HomeGeometry.homeBody(mode: .custom, customWidth: 440, customHeight: h, band: band)
            #expect(body.height <= max(CGFloat(h), 238))
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
        let body = CGSize(width: 532, height: 314)
        #expect(HomeGeometry.panel(body: body, sideButtons: true, bottomButtons: true) == CGSize(width: 660, height: 376))
        #expect(HomeGeometry.panel(body: body, sideButtons: false, bottomButtons: true) == CGSize(width: 532, height: 376))
        #expect(HomeGeometry.panel(body: body, sideButtons: false, bottomButtons: false) == body)
    }

    @Test func exploreKeepsHomeWidthAndFitsRows() {
        let home = CGSize(width: 532, height: 314)
        let nine = HomeGeometry.exploreBody(home: home, itemCount: 9, band: band)
        let thirteen = HomeGeometry.exploreBody(home: home, itemCount: 13, band: band)
        #expect(nine.width == 532 && thirteen.width == 532)
        #expect(thirteen.height - nine.height == HomeGeometry.exploreRow)
        #expect(nine.height - HomeGeometry.exploreBody(home: home, itemCount: 0, band: band).height == HomeGeometry.exploreRow)
    }

    @Test func modelMapsEachSizeModeToItsPanel() {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        let m = model(bench.defaults)
        #expect(m.sizeMode == IslandSizeMode.spacious && m.homeBody.height == 314)
        m.sizeMode = IslandSizeMode.compact
        #expect(m.homeBody.height == 238)
        m.sizeMode = IslandSizeMode.custom
        m.customWidth = 560
        m.customHeight = 640
        #expect(m.homeBody == CGSize(width: 560, height: 390))
        #expect(m.tileActions.count == 12)
        #expect(m.panelSize(body: m.homeBody) == CGSize(width: 688, height: 452))
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
