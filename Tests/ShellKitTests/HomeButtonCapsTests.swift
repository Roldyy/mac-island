import CoreGraphics
import Foundation
import IslandTestSupport
import Testing
@testable import ShellKit

/// The round buttons after the 3-per-side cap went: caps, one action once whatever its id form, a stored layout that
/// survives, and the decision to scroll a stack that does not fit.
@Suite struct HomeButtonCapsTests {
    private func filler(_ count: Int, side: HomeButtonSide, from start: Int = 0) -> [HomeButton] {
        (start..<start + count).map { HomeButton(actionID: "port.fill\($0)", side: side) }
    }

    // MARK: Caps

    @Test func capsAreEightPerSideAndSixAtTheBottom() {
        #expect(HomeButtonLayout.capacity(of: .left) == 8)
        #expect(HomeButtonLayout.capacity(of: .right) == 8)
        #expect(HomeButtonLayout.capacity(of: .bottom) == 6)
    }

    @Test func aSideAcceptsUpToItsCapAndRefusesTheNext() {
        var layout = HomeButtonLayout(buttons: filler(7, side: .left))
        #expect(layout.hasRoom(on: .left))
        let eighth = layout.add(actionID: "port.fill7", side: .left)
        #expect(eighth)
        #expect(!layout.hasRoom(on: .left))
        let ninth = layout.add(actionID: "port.fill8", side: .left)
        #expect(!ninth)
        #expect(layout.buttons(on: .left).count == 8)

        var bottom = HomeButtonLayout(buttons: filler(5, side: .bottom))
        let sixth = bottom.add(actionID: "port.fill5", side: .bottom)
        #expect(sixth)
        let seventh = bottom.add(actionID: "port.fill6", side: .bottom)
        #expect(!seventh)
    }

    @Test func movingIntoAFullSideIsRefusedAndFirstFreeSideSkipsIt() {
        var layout = HomeButtonLayout(buttons: filler(8, side: .left) + [HomeButton(actionID: "capture", side: .right)])
        let capture = layout.buttons(on: .right)[0].id
        let moved = layout.move(id: capture, to: .left)
        #expect(!moved)
        #expect(layout.firstFreeSide == .right)
    }

    @Test func sanitizingKeepsEightPerSideAndSixAtTheBottomAndDropsTheRest() {
        let raw = HomeButtonLayout(buttons: filler(10, side: .left) + filler(10, side: .bottom, from: 100))
        let clean = raw.sanitized()
        #expect(clean.buttons(on: .left).count == 8)
        #expect(clean.buttons(on: .bottom).count == 6)
        #expect(clean.buttons(on: .left).map(\.actionID) == (0..<8).map { "port.fill\($0)" })
    }

    // MARK: One action once

    @Test func theLegacyAndTheDockIdOfOneCommandAreTheSameAction() {
        #expect(HomeActionCatalog.dockID(forLegacy: "terminal") == "tab.terminal")
        #expect(HomeActionCatalog.dockID(forLegacy: "mixer") == "tab.audio")
        #expect(HomeActionCatalog.dockID(forLegacy: "keepawake") == "quick.keepawake")
        #expect(HomeActionCatalog.dockID(forLegacy: "settings") == "nav.settings")
        #expect(HomeActionCatalog.dockID(forLegacy: "explore") == "nav.explore")
        #expect(HomeActionCatalog.dockID(forLegacy: "ghost") == nil)

        var layout = HomeButtonLayout.initial  // has "terminal" on the left
        let again = layout.add(actionID: "tab.terminal", side: .right)
        #expect(!again, "the dock id of an action already shown is refused")
        #expect(layout.contains(actionID: "tab.terminal"))
        #expect(layout.contains(actionID: "terminal"))
    }

    @Test func addingFromTheCatalogStoresTheLegacyIdWhenThereIsOneAndTheDockIdOtherwise() {
        var layout = HomeButtonLayout(buttons: [])
        for id in ["quick.capture", "port.ocr", "feature.fans", "settings.island"] {
            let added = layout.add(actionID: id, side: .left)
            #expect(added, "\(id)")
        }
        #expect(layout.buttons(on: .left).map(\.actionID) == ["capture", "port.ocr", "feature.fans", "settings.island"])
        let twice = layout.add(actionID: "port.ocr", side: .right)
        #expect(!twice)
        let unknown = layout.add(actionID: "zzz")
        #expect(!unknown)
        let empty = layout.add(actionID: "tab.")
        #expect(!empty)
    }

    @Test func sanitizingDropsTheSecondFormOfOneAction() {
        let raw = HomeButtonLayout(buttons: [
            HomeButton(actionID: "terminal", side: .left), HomeButton(actionID: "tab.terminal", side: .right),
            HomeButton(actionID: "port.micmute", side: .right),
        ])
        #expect(raw.sanitized().buttons.map(\.actionID) == ["terminal", "port.micmute"])
    }

    // MARK: A stored layout is never lost

    @Test func aStoredThreePerSideLayoutDecodesUnchangedAndKeepsItsIds() throws {
        let json = """
        {"version":1,"buttons":[
        {"id":"6D0A0001-0000-4000-8000-000000000001","actionID":"terminal","side":"left","label":""},
        {"id":"6D0A0001-0000-4000-8000-000000000002","actionID":"clipboard","side":"left","label":"Notes"},
        {"id":"6D0A0001-0000-4000-8000-000000000007","actionID":"agents","side":"left","label":""},
        {"id":"6D0A0001-0000-4000-8000-000000000003","actionID":"settings","side":"right","label":""},
        {"id":"6D0A0001-0000-4000-8000-000000000005","actionID":"commands","side":"bottom","label":""}]}
        """
        let decoded = HomeButtonLayout.decode(Data(json.utf8))
        #expect(decoded.buttons.count == 5)
        #expect(decoded.buttons(on: .left).map(\.actionID) == ["terminal", "clipboard", "agents"])
        #expect(decoded.buttons[1].label == "Notes")
        #expect(decoded.buttons[0].id == UUID(uuidString: "6D0A0001-0000-4000-8000-000000000001"))
        // Re-encoding keeps the version-1 shape an older build reads.
        let again = try #require(decoded.encoded())
        #expect(HomeButtonLayout.decode(again) == decoded)
        let root = try #require(JSONSerialization.jsonObject(with: again) as? [String: Any])
        #expect(root["version"] as? Int == 1)
    }

    @Test func aDockCommandNotRegisteredRightNowIsKeptNotDropped() {
        // The app registers the port.* commands at launch; the pure layer must not forget one that is late.
        let raw = HomeButtonLayout(buttons: [HomeButton(actionID: "port.record", side: .right)])
        #expect(HomeButtonLayout.decode(raw.encoded()).buttons.map(\.actionID) == ["port.record"])
    }

    @MainActor @Test func eightButtonsAndDockIdsSurviveARelaunch() {
        let bench = TestDefaults.make(); defer { bench.cleanup() }
        let model = HomeModel(defaults: bench.defaults, volume: .unsupported("x"), brightness: .unsupported("x"))
        model.buttons = HomeButtonLayout(buttons: filler(8, side: .left) + filler(6, side: .bottom, from: 50))
        let expected = model.buttons
        let reopened = HomeModel(defaults: bench.defaults, volume: .unsupported("x"), brightness: .unsupported("x"))
        #expect(reopened.buttons == expected)
    }

    // MARK: Ordering

    @Test func reorderingWalksTheWholeEightButtonColumn() {
        var layout = HomeButtonLayout(buttons: filler(8, side: .left))
        let first = layout.buttons[0].id
        for _ in 0..<7 {
            let ok = layout.reorder(id: first, by: 1)
            #expect(ok)
        }
        let past = layout.reorder(id: first, by: 1)
        #expect(!past)
        #expect(layout.buttons(on: .left).last?.id == first)
        #expect(layout.buttons(on: .left).count == 8)
    }

    // MARK: Scroll decision

    @Test func aStackScrollsOnlyWhenItsContentIsLongerThanTheRoom() {
        // 44 pt buttons, 12 pt apart: n buttons are 56 n - 12 long.
        #expect(HomeButtonStack.contentLength(count: 0, item: 44, spacing: 12) == 0)
        #expect(HomeButtonStack.contentLength(count: 1, item: 44, spacing: 12) == 44)
        #expect(HomeButtonStack.contentLength(count: 3, item: 44, spacing: 12) == 156)
        #expect(HomeButtonStack.contentLength(count: 8, item: 44, spacing: 12) == 436)
        #expect(!HomeButtonStack.needsScroll(count: 3, item: 44, spacing: 12, available: 156))
        #expect(HomeButtonStack.needsScroll(count: 3, item: 44, spacing: 12, available: 155.5))
        #expect(HomeButtonStack.needsScroll(count: 8, item: 44, spacing: 12, available: 310))
        #expect(!HomeButtonStack.needsScroll(count: 0, item: 44, spacing: 12, available: 0))
    }

    @Test func theDefaultThreeButtonsNeverScrollInAnyHomeSize() {
        for mode in IslandSizeMode.allCases {
            let body = HomeGeometry.homeBody(mode: mode, customWidth: 360, customHeight: 260, band: 38)
            let room = HomeButtonStack.sideAvailable(bodyHeight: body.height, band: 38)
            #expect(!HomeButtonStack.needsScroll(count: 3, item: HomeGeometry.circleDiameter,
                                                 spacing: HomeButtonStack.spacing, available: room), "\(mode)")
        }
    }

    @Test func roomOfTheColumnAndOfTheBottomRow() {
        #expect(HomeButtonStack.sideAvailable(bodyHeight: 354, band: 38) == 354 - 38 - HomeGeometry.bandGap)
        #expect(HomeButtonStack.sideAvailable(bodyHeight: 10, band: 38) == 0)
        // The mark takes 92 pt at each end of the bottom row.
        #expect(HomeButtonStack.bottomAvailable(panelWidth: 660) == 476)
        #expect(HomeButtonStack.bottomAvailable(panelWidth: 100) == 0)
        // Six buttons fit a spacious panel with side columns, not a bare compact one.
        let six = HomeButtonStack.contentLength(count: 6, item: 44, spacing: 12)
        #expect(six <= HomeButtonStack.bottomAvailable(panelWidth: HomeGeometry.spaciousWidth + 2 * HomeGeometry.sideColumn))
        #expect(six > HomeButtonStack.bottomAvailable(panelWidth: HomeGeometry.compactWidth))
    }

    // MARK: Picker, settings text, tooltip

    @Test func thePickerOffersEveryCatalogCommandNoButtonShowsYet() {
        let catalog = [
            DockCommand(id: "tab.terminal", title: "Terminal", systemImage: "terminal", category: .panels) {},
            DockCommand(id: "port.ocr", title: "OCR", systemImage: "text.viewfinder", category: .capture) {},
            DockCommand(id: "feature.fans", title: "Basculer : Ventilos", systemImage: "fan", category: .features) {},
        ]
        let layout = HomeButtonLayout.initial  // already has the Terminal button, stored as "terminal"
        #expect(HomeButtonPicker.candidates(catalog, layout: layout).map(\.id) == ["port.ocr", "feature.fans"])
        let found = ExtraDockCatalog.search(HomeButtonPicker.candidates(catalog, layout: layout), query: "ventilo")
        #expect(found.map(\.id) == ["feature.fans"])
    }

    @Test func theSettingsCaptionStatesTheRealCaps() {
        #expect(IslandLayoutSettings.buttonsCaption == "Jusqu’à 8 boutons par côté, 6 en bas, chaque action une seule fois.")
    }

    @Test func theTooltipKeepsTheTitleAndAddsTheReasonWhenDisabled() {
        let command = DockCommand(id: "port.ocr", title: "OCR", systemImage: "x", category: .capture) {}
        #expect(HomeDockCircleButton.help(title: "OCR", command: command, reason: nil, id: "port.ocr") == "OCR")
        #expect(HomeDockCircleButton.help(title: "OCR", command: command, reason: "désactivée", id: "port.ocr") == "OCR : désactivée")
        #expect(HomeDockCircleButton.help(title: "Commande introuvable", command: nil, reason: nil, id: "port.x")
                == "Commande introuvable : port.x")
    }
}
