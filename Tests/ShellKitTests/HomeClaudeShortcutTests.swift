import Foundation
import IslandKit
import IslandTestSupport
import Testing
@testable import ShellKit

@MainActor
@Suite struct HomeClaudeShortcutTests {
    private func model(_ defaults: UserDefaults) -> HomeModel {
        HomeModel(defaults: defaults, volume: .unsupported("x"), brightness: .unsupported("x"))
    }

    /// A v1 layout saved before the Claude shortcut existed: left has two buttons.
    private static let oldLayoutJSON = """
    {"version":1,"buttons":[
    {"id":"6D0A0001-0000-4000-8000-000000000001","actionID":"explore","side":"left","label":""},
    {"id":"6D0A0001-0000-4000-8000-000000000002","actionID":"clipboard","side":"left","label":""},
    {"id":"6D0A0001-0000-4000-8000-000000000003","actionID":"settings","side":"right","label":""}]}
    """

    @Test func anOldStoredLayoutGetsTheClaudeButtonOnceAndKeepsItsOwnButtons() {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        bench.defaults.set(Data(Self.oldLayoutJSON.utf8), forKey: HomeModel.Keys.layout)
        let first = model(bench.defaults)
        #expect(first.buttons.buttons(on: .left).map(\.actionID) == ["explore", "clipboard", "agents"])
        #expect(first.buttons.buttons(on: .right).map(\.actionID) == ["settings"])
        // The user removes it: the next launch does not bring it back.
        first.buttons.remove(id: first.buttons.buttons(on: .left)[2].id)
        let second = model(bench.defaults)
        #expect(!second.buttons.contains(actionID: "agents"))
    }

    @Test func aFullLayoutIsLeftAloneAndAFreshInstallHasItByDefault() {
        let full = HomeButtonLayout(buttons: [
            HomeButton(actionID: "explore", side: .left), HomeButton(actionID: "clipboard", side: .left),
            HomeButton(actionID: "mixer", side: .left), HomeButton(actionID: "settings", side: .right),
            HomeButton(actionID: "capture", side: .right), HomeButton(actionID: "lockScreen", side: .right),
            HomeButton(actionID: "commands", side: .bottom), HomeButton(actionID: "keepawake", side: .bottom),
            HomeButton(actionID: "cleaning", side: .bottom),
        ])
        #expect(full.addingClaudeShortcut() == full)
        let spill = HomeButtonLayout(buttons: Array(full.buttons.prefix(3)))
        #expect(spill.addingClaudeShortcut().buttons(on: .right).map(\.actionID) == ["agents"])
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        #expect(model(bench.defaults).buttons.contains(actionID: "agents"))
    }

    @Test func theClaudeTileIsOneOfTheFirstRowsOfTheGrid() {
        let actions = HomeActionCatalog.tileIDs.compactMap(HomeActionCatalog.action)
        let features = ShellDescriptors.all.map { HomeFeature(id: $0.id, title: $0.title, systemImage: $0.systemImage) }
        let tiles = HomeTileCatalog.merged(actions: actions, features: features, enabled: { _ in true }, hidden: [])
        #expect(tiles.prefix(5).map(\.id).contains("agents"))
        #expect(tiles.filter { $0.featureID == "agents" }.count == 1)
    }

    @Test func statusFollowsTheClaudeWing() {
        let working = ActivityLayout(leading: CompactItem(symbol: "sparkles", status: .info), trailing: nil, dot: nil)
        let waiting = ActivityLayout(leading: CompactItem(symbol: "hand.raised.fill", status: .warning), trailing: nil, dot: nil)
        let cleaning = ActivityLayout(leading: CompactItem(symbol: "sparkles", text: "0:30", status: .info), trailing: nil, dot: nil)
        #expect(ClaudeHomeStatus.from(layout: .empty) == .idle)
        #expect(ClaudeHomeStatus.from(layout: working) == .working)
        #expect(ClaudeHomeStatus.from(layout: waiting) == .waiting)
        #expect(ClaudeHomeStatus.from(layout: cleaning) == .idle)
        #expect(ClaudeHomeStatus.idle.label == nil)
    }

    @Test func launcherChecksExistenceAndOnlyThenOpens() {
        var opened: [URL] = []
        var installed = false
        let launcher = ClaudeAppLauncher(exists: { _ in installed }, open: { opened.append($0) })
        #expect(!launcher.isAvailable)
        #expect(launcher.unavailableReason == ClaudeAppLauncher.missingReason)
        #expect(!launcher.launch())
        #expect(opened.isEmpty)
        installed = true
        #expect(launcher.unavailableReason == nil)
        #expect(launcher.launch())
        #expect(opened == [ClaudeAppLauncher.defaultURL])
    }
}
