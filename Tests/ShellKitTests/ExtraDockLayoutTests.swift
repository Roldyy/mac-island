import Foundation
import IslandTestSupport
import Testing
@testable import ShellKit

/// The extra dock's pure model: add, remove, reorder, the versioned JSON and its migration.
@Suite struct ExtraDockLayoutTests {
    @Test func addRefusesDuplicatesEmptyIdsAndAFullDock() {
        var layout = ExtraDockLayout(ids: [])
        let first = layout.add("tab.agents")
        let again = layout.add("tab.agents")
        let empty = layout.add("")
        #expect(first && !again && !empty)
        for n in 1..<ExtraDockLayout.maxItems {
            let added = layout.add("x.\(n)")
            #expect(added)
        }
        #expect(layout.isFull)
        let overflow = layout.add("one.too.many")
        #expect(!overflow)
        #expect(layout.ids.count == ExtraDockLayout.maxItems)
    }

    @Test func removeDropsOnlyThatCommand() {
        var layout = ExtraDockLayout(ids: ["a", "b", "c"])
        layout.remove("b")
        layout.remove("zzz")
        #expect(layout.ids == ["a", "c"])
    }

    @Test func moveBeforeATargetOrToTheEnd() {
        var layout = ExtraDockLayout(ids: ["a", "b", "c", "d"])
        let toFront = layout.move("d", before: "a")
        #expect(toFront && layout.ids == ["d", "a", "b", "c"])
        let forward = layout.move("d", before: "c")
        #expect(forward && layout.ids == ["a", "b", "d", "c"])
        let toEnd = layout.move("a", before: nil)
        #expect(toEnd && layout.ids == ["b", "d", "c", "a"])
        let onItself = layout.move("b", before: "b")
        #expect(onItself && layout.ids == ["b", "d", "c", "a"])
        let unknownMoved = layout.move("nope", before: "a")
        let unknownTarget = layout.move("a", before: "nope")
        #expect(!unknownMoved && !unknownTarget && layout.ids == ["b", "d", "c", "a"])
    }

    @Test func reorderSwapsWithTheNeighbourAndStopsAtTheEnds() {
        var layout = ExtraDockLayout(ids: ["a", "b", "c"])
        let up = layout.reorder("b", by: -1)
        let upAgain = layout.reorder("b", by: -1)
        #expect(up && !upAgain && layout.ids == ["b", "a", "c"])
        let down = layout.reorder("c", by: 1)
        #expect(!down)
        let unknown = layout.reorder("zzz", by: 1)
        #expect(!unknown)
    }

    @Test func sanitizedKeepsUnknownIdsButNotRepeatsEmptiesOrOverflow() {
        let many = (0..<30).map { "id.\($0)" }
        let layout = ExtraDockLayout(ids: ["a", "", "a", "b"] + many).sanitized()
        #expect(layout.ids.count == ExtraDockLayout.maxItems)
        #expect(Array(layout.ids.prefix(3)) == ["a", "b", "id.0"])
        #expect(Set(layout.ids).count == layout.ids.count)
    }

    @Test func dragPayloadRoundTripsAndRefusesForeignText() {
        let payload = ExtraDockLayout.dragPayload("tab.agents")
        #expect(ExtraDockLayout.dragID(from: payload) == "tab.agents")
        #expect(ExtraDockLayout.dragID(from: "tab.agents") == nil)
        #expect(ExtraDockLayout.dragID(from: ExtraDockLayout.dragPayload("")) == nil)
    }

    // MARK: codec and migration

    @Test func theStoredFormIsVersionedJSONAndRoundTrips() throws {
        let layout = ExtraDockLayout(ids: ["tab.agents", "port.micmute"])
        let data = try #require(layout.encoded())
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["version"] as? Int == 1)
        #expect(object["ids"] as? [String] == ["tab.agents", "port.micmute"])
        #expect(ExtraDockLayout.decode(data) == layout)
    }

    @Test func nothingStoredDamagedOrNewerGivesTheDefaults() throws {
        #expect(ExtraDockLayout.decode(nil) == .initial)
        #expect(ExtraDockLayout.decode(Data("not json".utf8)) == .initial)
        #expect(ExtraDockLayout.decode(Data(#"{"version":99,"ids":["a"]}"#.utf8)) == .initial)
        #expect(ExtraDockLayout.decode(Data(#"{"ids":["a"]}"#.utf8)) == .initial)
    }

    @Test func aStoredEmptyDockStaysEmpty() throws {
        let data = try #require(ExtraDockLayout(ids: []).encoded())
        #expect(ExtraDockLayout.decode(data).ids.isEmpty)
    }

    @Test func versionZeroBareArrayIsMigratedToCurrentNames() {
        let data = Data(#"["keepawake","terminal","tab.shelf","port.micmute","keepawake"]"#.utf8)
        #expect(ExtraDockLayout.decode(data).ids == ["quick.keepawake", "tab.terminal", "tab.shelf", "port.micmute"])
    }

    @Test func everyLegacyIdMapsToANameTheCatalogUses() {
        for (old, current) in ExtraDockLayout.legacyIDs {
            #expect(!old.contains("."), "\(old) is a short version-0 id")
            #expect(["quick.", "nav.", "tab."].contains { current.hasPrefix($0) }, "\(old) -> \(current)")
        }
    }

    @Test func defaultsAreFreeOfRepeatsAndFitTheDock() {
        let ids = ExtraDockLayout.initial.ids
        #expect(Set(ids).count == ids.count)
        #expect(ids.count <= ExtraDockLayout.maxItems)
        #expect(ExtraDockLayout.initial.sanitized() == .initial)
    }

    // MARK: the home model keeps it in defaults

    @MainActor @Test func homeModelStartsOnTheDefaultsAndPersistsEveryChange() throws {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        let home = HomeModel(defaults: bench.defaults)
        #expect(home.extraDock == .initial)
        #expect(home.showsExtraDock)
        home.extraDock.add("port.micmute")
        home.showsExtraDock = false
        let again = HomeModel(defaults: bench.defaults)
        #expect(again.extraDock.ids.last == "port.micmute")
        #expect(!again.showsExtraDock)
    }

    @MainActor @Test func homeModelRewritesAVersionZeroBlobOnce() throws {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        bench.defaults.set(Data(#"["capture","settings"]"#.utf8), forKey: HomeModel.Keys.extraDock)
        let home = HomeModel(defaults: bench.defaults)
        #expect(home.extraDock.ids == ["quick.capture", "nav.settings"])
        let stored = try #require(bench.defaults.data(forKey: HomeModel.Keys.extraDock))
        let object = try #require(try JSONSerialization.jsonObject(with: stored) as? [String: Any])
        #expect(object["version"] as? Int == 1)
    }

    // MARK: geometry

    @Test func theDockAddsExactlyItsRowAndLeavesTheBottomRowAlone() {
        let band = ShellLayout.topBandHeight
        for mode in IslandSizeMode.allCases {
            let without = HomeGeometry.homeBody(mode: mode, customWidth: 440, customHeight: 480, band: band, tileCount: 4)
            let with = HomeGeometry.homeBody(mode: mode, customWidth: 440, customHeight: 480, band: band, tileCount: 4,
                                             dock: HomeGeometry.extraDockSpace)
            #expect(with.width == without.width, "\(mode)")
            #expect(with.height - without.height == HomeGeometry.extraDockSpace, "\(mode)")
        }
        #expect(HomeGeometry.bottomRow == 62)
        let panel = HomeGeometry.panel(body: CGSize(width: 500, height: 300), sideButtons: false, bottomButtons: true)
        #expect(panel.height == 300 + HomeGeometry.bottomRow)
    }

    @Test func aCustomHeightKeepsItsTotalWhenTheDockShows() {
        let band = ShellLayout.topBandHeight
        let rows = HomeGeometry.tileRows(for: .custom, customHeight: 560, band: band)
        let withDock = HomeGeometry.tileRows(for: .custom, customHeight: 560, band: band, dock: HomeGeometry.extraDockSpace)
        #expect(withDock <= rows)
        let body = HomeGeometry.homeBody(mode: .custom, customWidth: 440, customHeight: 560, band: band, dock: HomeGeometry.extraDockSpace)
        #expect(body.height <= 560)
    }
}
