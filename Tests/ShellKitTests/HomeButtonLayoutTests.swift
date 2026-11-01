import Foundation
import IslandTestSupport
import Testing
@testable import ShellKit

@Suite struct HomeButtonLayoutTests {
    @Test func defaultsFollowTheScreenshotLayout() {
        let layout = HomeButtonLayout.initial
        #expect(layout.buttons(on: .left).map(\.actionID) == ["terminal", "clipboard", "agents"])
        #expect(layout.buttons(on: .right).map(\.actionID) == ["settings", "mixer"])
        #expect(layout.buttons(on: .bottom).map(\.actionID) == ["commands", "keepawake"])
        #expect(layout.sanitized() == layout)  // every default is a known action
    }

    @Test func addRefusesDuplicatesUnknownActionsAndFullSides() {
        var layout = HomeButtonLayout(buttons: [])
        let ok1 = layout.add(actionID: "capture", side: .left)
        #expect(ok1)
        let ok2 = layout.add(actionID: "capture", side: .right)
        #expect(!ok2)
        let ok3 = layout.add(actionID: "nope")
        #expect(!ok3)
        let ok4 = layout.add(actionID: "lockScreen", side: .left)
        #expect(ok4)
        let ok5 = layout.add(actionID: "cleaning", side: .left)
        #expect(ok5)
        let ok6 = layout.add(actionID: "monitor", side: .left)
        #expect(!ok6)
        let ok7 = layout.add(actionID: "monitor")
        #expect(ok7)
        #expect(layout.buttons(on: .right).map(\.actionID) == ["monitor"])
    }

    @Test func moveAndReorderKeepTheOrderOfTheRow() {
        var layout = HomeButtonLayout.initial
        let explore = layout.buttons(on: .left)[0].id
        let ok8 = layout.reorder(id: explore, by: 1)
        #expect(ok8)
        #expect(layout.buttons(on: .left).map(\.actionID) == ["clipboard", "terminal", "agents"])
        let ok9 = layout.reorder(id: explore, by: 1)
        #expect(ok9)
        let ok9b = layout.reorder(id: explore, by: 1)
        #expect(!ok9b)
        let ok10 = layout.move(id: explore, to: .bottom)
        #expect(ok10)
        #expect(layout.buttons(on: .bottom).map(\.actionID) == ["commands", "keepawake", "terminal"])
        let clipboard = layout.buttons(on: .left)[0].id
        let ok11 = layout.move(id: clipboard, to: .bottom)
        #expect(!ok11)
        layout.remove(id: clipboard)
        #expect(layout.buttons(on: .left).map(\.actionID) == ["agents"])
    }

    @Test func sanitizingDropsUnknownRepeatedAndExtraButtons() {
        let raw = HomeButtonLayout(buttons: [
            HomeButton(actionID: "explore", side: .left), HomeButton(actionID: "explore", side: .right),
            HomeButton(actionID: "ghost", side: .left),
            HomeButton(actionID: "capture", side: .bottom), HomeButton(actionID: "lockScreen", side: .bottom),
            HomeButton(actionID: "cleaning", side: .bottom), HomeButton(actionID: "monitor", side: .bottom),
        ])
        #expect(raw.sanitized().buttons.map(\.actionID) == ["explore", "capture", "lockScreen", "cleaning"])
    }

    @Test func aliasesFromAnotherBuildMapToHereActions() {
        let raw = HomeButtonLayout(buttons: [
            HomeButton(actionID: "control.keepAwake", side: .bottom), HomeButton(actionID: "controls", side: .bottom),
        ])
        #expect(raw.sanitized().buttons.map(\.actionID) == ["keepawake", "commands"])
    }

    @Test func encodingRoundTripsAndKeepsTheOldAppsJSONShape() throws {
        let data = try #require(HomeButtonLayout.initial.encoded())
        #expect(HomeButtonLayout.decode(data) == HomeButtonLayout.initial)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["version"] as? Int == 1)
        let first = try #require((json["buttons"] as? [[String: Any]])?.first)
        #expect(Set(first.keys) == ["id", "actionID", "side", "label"])
    }

    @Test func damagedOrNewerDataFallsBackToDefaultsButAnEmptyListStaysEmpty() throws {
        #expect(HomeButtonLayout.decode(nil) == .initial)
        #expect(HomeButtonLayout.decode(Data("not json".utf8)) == .initial)
        #expect(HomeButtonLayout.decode(Data(#"{"version":9,"buttons":[]}"#.utf8)) == .initial)
        #expect(HomeButtonLayout.decode(Data(#"{"version":1,"buttons":[]}"#.utf8)).buttons.isEmpty)
        let unknown = #"{"version":1,"buttons":[{"id":"6D0A0001-0000-4000-8000-0000000000AA","actionID":"ghost","side":"left","label":""}]}"#
        #expect(HomeButtonLayout.decode(Data(unknown.utf8)) == .initial)
    }

    @MainActor @Test func theLayoutAndOrderPersistThroughTheModel() {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        let model = HomeModel(defaults: bench.defaults, volume: .unsupported("x"), brightness: .unsupported("x"))
        #expect(model.buttons == .initial)
        let clipboard = model.buttons.buttons(on: .left)[1].id
        model.buttons.reorder(id: clipboard, by: -1)
        model.buttons.remove(id: model.buttons.buttons(on: .right)[0].id)
        model.buttons.add(actionID: "capture", side: .right)
        let expected = model.buttons

        let reopened = HomeModel(defaults: bench.defaults, volume: .unsupported("x"), brightness: .unsupported("x"))
        #expect(reopened.buttons == expected)
        #expect(reopened.buttons.buttons(on: .left).map(\.actionID) == ["clipboard", "terminal", "agents"])
        #expect(reopened.buttons.buttons(on: .right).map(\.actionID) == ["mixer", "capture"])
    }
}


@MainActor
@Suite struct HomeExplorerReplacementTests {
    @Test func theExplorerButtonBecomesTerminalInPlace() {
        let layout = HomeButtonLayout(buttons: [
            HomeButton(actionID: "clipboard", side: .left), HomeButton(actionID: "explore", side: .left),
            HomeButton(actionID: "settings", side: .right),
        ])
        let replaced = layout.replacingExplorerWithTerminal()
        #expect(replaced.buttons(on: .left).map(\.actionID) == ["clipboard", "terminal"])
        #expect(replaced.buttons(on: .right).map(\.actionID) == ["settings"])
    }

    @Test func itJustDisappearsWhenTerminalIsAlreadyThere() {
        let layout = HomeButtonLayout(buttons: [
            HomeButton(actionID: "explore", side: .left), HomeButton(actionID: "terminal", side: .right),
        ])
        let replaced = layout.replacingExplorerWithTerminal()
        #expect(replaced.buttons.map(\.actionID) == ["terminal"])
    }

    @Test func aLayoutWithoutItIsUntouchedAndTheMigrationRunsOnce() {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        let json = #"{"version":1,"buttons":[{"id":"6D0A0001-0000-4000-8000-000000000001","actionID":"explore","side":"left","label":""}]}"#
        bench.defaults.set(Data(json.utf8), forKey: HomeModel.Keys.layout)
        bench.defaults.set(true, forKey: HomeModel.Keys.claudeShortcutSeeded)
        let first = HomeModel(defaults: bench.defaults, volume: .unsupported("x"), brightness: .unsupported("x"))
        #expect(first.buttons.buttons(on: .left).map(\.actionID) == ["terminal"])
        // The user adds Explorer back: the next launch does not remove it again.
        first.buttons.add(actionID: "explore", side: .left)
        let second = HomeModel(defaults: bench.defaults, volume: .unsupported("x"), brightness: .unsupported("x"))
        #expect(second.buttons.contains(actionID: "explore"))
    }
}
