import CoreGraphics
import Foundation
import IslandTestSupport
import Testing
@testable import ShellKit

/// The merged list behind the home grid and the Explorer: dedupe, order, hidden set, dimmed tail, rows per mode.
@MainActor
@Suite struct HomeTileCatalogTests {
    private let band = ShellLayout.topBandHeight

    private var features: [HomeFeature] {
        ShellDescriptors.all.map { HomeFeature(id: $0.id, title: $0.title, systemImage: $0.systemImage) }
    }

    private var actions: [HomeAction] { HomeActionCatalog.tileIDs.compactMap(HomeActionCatalog.action) }

    private func merged(enabled: Set<String>? = nil, hidden: Set<String> = [], showHidden: Bool = false,
                        features overrideFeatures: [HomeFeature]? = nil) -> [HomeTileItem] {
        HomeTileCatalog.merged(actions: actions, features: overrideFeatures ?? features,
                               enabled: { enabled?.contains($0) ?? true }, hidden: hidden, showHidden: showHidden)
    }

    // MARK: merge, dedupe, order

    @Test func everyFeatureAndEveryActionAppearsOnceAllEnabled() {
        let tiles = merged()
        #expect(Set(tiles.map(\.id)).count == tiles.count)
        // 13 shortcuts of the user + the 3 features no action covers.
        #expect(tiles.map(\.id) == [
            "mixer", "keepawake", "agents", "commands", "capture", "lockScreen", "cleaning", "monitor",
            "shelf", "clipboard", "terminal", "nowplaying", "settings",
            "fans", "finder", "dock",
        ])
        #expect(tiles.allSatisfy { $0.isEnabled })
        // Every Explorer feature is reachable from exactly one tile.
        for feature in features { #expect(tiles.filter { $0.featureID == feature.id }.count == 1, "\(feature.id)") }
    }

    @Test func anActionAndItsFeatureAreOneTileUnderTheActionsName() {
        let tiles = merged()
        func tile(_ id: String) -> HomeTileItem? { tiles.first { $0.id == id } }
        #expect(tile("agents")?.title == "Claude" && tile("agents")?.featureID == "agents")
        #expect(tile("mixer")?.title == "Mélangeur de volume" && tile("mixer")?.featureID == "audio")
        #expect(tile("keepawake")?.title == "Garder éveillé" && tile("keepawake")?.featureID == "keepawake")
        #expect(tile("commands")?.featureID == "commandbar")
        #expect(tile("monitor")?.featureID == "monitor")
        #expect(tile("audio") == nil && tile("commandbar") == nil)
        #expect(tile("capture")?.featureID == nil && tile("lockScreen")?.featureID == nil)
        #expect(tile("settings")?.title == "Réglages")
        #expect(tile("finder")?.source == .feature)
    }

    @Test func aDuplicatedActionIdIsKeptOnce() {
        let mixer = HomeActionCatalog.action("mixer")!
        let tiles = HomeTileCatalog.merged(actions: [mixer, mixer], features: features, enabled: { _ in true }, hidden: [])
        #expect(tiles.filter { $0.id == "mixer" }.count == 1)
    }

    @Test func theUsersOrderComesFirstThenTheOtherEnabledFeaturesInExplorerOrder() {
        let tiles = merged(enabled: ["terminal", "agents", "audio", "fans", "finder", "dock"])
        let ids = tiles.map(\.id)
        // Enabled, user's order: mixer (audio), agents, capture, lockScreen, cleaning, terminal, settings.
        #expect(Array(ids.prefix(7)) == ["mixer", "agents", "capture", "lockScreen", "cleaning", "terminal", "settings"])
        // Then the enabled features no action covers, in Explorer order.
        #expect(Array(ids[7..<10]) == ["fans", "finder", "dock"])
        #expect(tiles[7..<10].allSatisfy { $0.isEnabled })
        #expect(tiles[10...].allSatisfy { !$0.isEnabled })
    }

    @Test func disabledFeaturesGoLastDimmedInExplorerOrder() {
        // Harold's real case: terminal, agents and clipboard on, everything else off.
        let tiles = merged(enabled: ["terminal", "agents", "clipboard"])
        let on = tiles.filter(\.isEnabled).map(\.id)
        let off = tiles.filter { !$0.isEnabled }.map(\.id)
        #expect(on == ["agents", "capture", "lockScreen", "cleaning", "clipboard", "terminal", "settings"])
        #expect(off == ["shelf", "nowplaying", "mixer", "keepawake", "monitor", "fans", "commands", "finder", "dock"])
        #expect(tiles.map(\.id) == on + off)
        #expect(tiles.count == 16)
    }

    @Test func aFeatureWithNoTabCountsAsOff() {
        let tiles = merged(features: features.filter { $0.id != "monitor" })
        let monitor = tiles.first { $0.id == "monitor" }
        #expect(monitor?.isEnabled == false)
        #expect(tiles.last?.id == "monitor")
        // Quick actions with no feature stay live even with no tab at all.
        let bare = merged(features: [])
        #expect(bare.filter(\.isEnabled).map(\.id) == ["capture", "lockScreen", "cleaning", "settings"])
    }

    @Test func aPortedFeatureWithATabGetsATileAfterTheBuiltInOnes() {
        let extra = HomeFeature(id: "switcher", title: "Sélecteur", systemImage: "rectangle.on.rectangle")
        let tiles = merged(features: features + [extra])
        #expect(tiles.last?.id == "switcher" && tiles.last?.source == .feature)
        #expect(tiles.count == 17)
    }

    // MARK: hidden set

    @Test func hiddenTilesLeaveTheHomeButStayInTheExplorerFlagged() {
        let home = merged(hidden: ["capture", "finder", "ghost"])
        #expect(!home.map(\.id).contains("capture") && !home.map(\.id).contains("finder"))
        #expect(home.count == 14)
        let explorer = merged(hidden: ["capture", "finder"], showHidden: true)
        #expect(explorer.count == 16)
        #expect(explorer.filter(\.isHidden).map(\.id) == ["capture", "finder"])
        // Same order either way: hiding never reshuffles the rest.
        #expect(explorer.filter { !$0.isHidden }.map(\.id) == home.map(\.id))
    }

    @Test func aHiddenDisabledTileIsGoneToo() {
        let tiles = merged(enabled: ["terminal"], hidden: ["dock", "shelf"])
        #expect(!tiles.map(\.id).contains("dock") && !tiles.map(\.id).contains("shelf"))
    }

    @Test func hiddenSetPersistsAsAJSONArrayInAnIsolatedSuite() {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        let home = HomeModel(defaults: bench.defaults, volume: .unsupported("x"), brightness: .unsupported("x"))
        #expect(home.hiddenTiles.isEmpty)
        home.hideTile("capture")
        home.hideTile("dock")
        home.hideTile("capture")
        #expect(home.hiddenTiles == ["capture", "dock"])
        let raw = bench.defaults.data(forKey: "notchHomeHiddenTiles")
        #expect(raw.flatMap { try? JSONDecoder().decode([String].self, from: $0) } == ["capture", "dock"])
        let again = HomeModel(defaults: bench.defaults, volume: .unsupported("x"), brightness: .unsupported("x"))
        #expect(again.hiddenTiles == ["capture", "dock"])
        again.showTile("capture")
        #expect(HomeModel(defaults: bench.defaults, volume: .unsupported("x"), brightness: .unsupported("x")).hiddenTiles == ["dock"])
        again.showAllTiles()
        #expect(HomeModel(defaults: bench.defaults, volume: .unsupported("x"), brightness: .unsupported("x")).hiddenTiles.isEmpty)
    }

    @Test func damagedHiddenValuesNeverHideTheGrid() {
        #expect(HomeHiddenTiles.decode(nil).isEmpty)
        #expect(HomeHiddenTiles.decode(Data("not json".utf8)).isEmpty)
        #expect(HomeHiddenTiles.decode(Data("{\"a\":1}".utf8)).isEmpty)
        #expect(HomeHiddenTiles.decode(42).isEmpty)
        #expect(HomeHiddenTiles.decode("[\"a\",\"b\"]") == ["a", "b"])
        #expect(HomeHiddenTiles.encode(["b", "a"]) == Data("[\"a\",\"b\"]".utf8))
    }

    // MARK: right-click menus

    @Test func tileMenuOffersHideOrShowAndTheIslandMenuShowAllOnlyWhenSomethingIsHidden() {
        let tiles = merged(hidden: ["dock"], showHidden: true)
        let dock = tiles.first { $0.id == "dock" }!, capture = tiles.first { $0.id == "capture" }!
        #expect(HomeTileMenu.entries(for: capture) == [.hide])
        #expect(HomeTileMenu.entries(for: dock) == [.show])
        #expect(HomeTileMenu.Entry.hide.title == "Masquer ce raccourci")
        #expect(HomeTileMenu.Entry.show.title == "Afficher le raccourci")
        #expect(HomeTileMenu.showAllTitle == "Tout afficher")
        #expect(!HomeTileMenu.showAllEnabled(hidden: []))
        #expect(HomeTileMenu.showAllEnabled(hidden: ["dock"]))
    }

    // MARK: rows and heights

    @Test func columnsAreFiveExceptWhenCompactOrNarrow() {
        #expect(HomeGeometry.tileColumns(for: .compact, width: 600) == 4)
        #expect(HomeGeometry.tileColumns(for: .spacious, width: 360) == 5)
        #expect(HomeGeometry.tileColumns(for: .custom, width: 499) == 4)
        #expect(HomeGeometry.tileColumns(for: .custom, width: 500) == 5)
    }

    @Test func visibleRowsFollowTheModeAndNeverShowEmptyRows() {
        func rows(_ mode: IslandSizeMode, count: Int, height: Double = 480) -> Int {
            HomeGeometry.visibleTileRows(for: mode, customWidth: 560, customHeight: height, band: band, tileCount: count)
        }
        // 25 tiles: 5 columns give 5 rows, 4 give 7; each mode keeps its cap and the grid scrolls.
        #expect(rows(.compact, count: 25) == 2)
        #expect(rows(.spacious, count: 25) == 3)
        #expect(rows(.custom, count: 25, height: 640) == 5)  // 5 rows of 5 fit, cap 6
        #expect(rows(.custom, count: 60, height: 640) == 6)
        #expect(rows(.custom, count: 60, height: 480) == 4)
        // Few tiles: no empty rows.
        #expect(rows(.spacious, count: 7) == 2)
        #expect(rows(.spacious, count: 3) == 1)
        #expect(rows(.compact, count: 3) == 1)
        #expect(rows(.spacious, count: 0) == 1)
    }

    @Test func heightIsBoundedWhateverTheTileCount() {
        for mode in IslandSizeMode.allCases {
            let few = HomeGeometry.homeBody(mode: mode, customWidth: 560, customHeight: 640, band: band, tileCount: 5)
            let many = HomeGeometry.homeBody(mode: mode, customWidth: 560, customHeight: 640, band: band, tileCount: 500)
            let unlimited = HomeGeometry.homeBody(mode: mode, customWidth: 560, customHeight: 640, band: band)
            #expect(many == unlimited && few.height <= many.height)
            #expect(many.height <= 640)
        }
        #expect(HomeGeometry.homeBody(mode: .spacious, customWidth: 0, customHeight: 0, band: band, tileCount: 500).height == 354)
    }

    @Test func theFadeShowsOnlyOnTheEdgesThatHideRows() {
        // 7 rows, 3 visible.
        func edges(_ top: Int) -> [Bool] {
            let e = HomeGeometry.hiddenEdges(topRow: top, visibleRows: 3, totalRows: 7)
            return [e.above, e.below]
        }
        #expect(edges(0) == [false, true])
        #expect(edges(2) == [true, true])
        #expect(edges(4) == [true, false])
    }

    @Test func tilesFitTheirRowHeight() {
        // Glyph 28 + gap 4 + two 11 pt lines (26) + top padding 2 = 60, inside the 64 pt row.
        #expect(HomeGeometry.tileRow == 64)
        #expect(28 + 4 + 26 + 2 <= HomeGeometry.tileRow)
    }

    @Test func rowsAreChunkedByColumns() {
        let rows = HomeTileCatalog.rows(Array(1...12), columns: 5)
        #expect(rows.map(\.count) == [5, 5, 2])
        #expect(HomeTileCatalog.rows([Int](), columns: 5).isEmpty)
        #expect(HomeTileCatalog.rows([1, 2], columns: 0).isEmpty)
    }
}
