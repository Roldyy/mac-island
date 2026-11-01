import Testing
@testable import CommandBarFeature

/// The command bar is the ported one: this target keeps the names the shell calls (tab id, commands, the button).
/// The engine, the sources, the shortcut and the safety rules are tested in `PortKitTests/CommandBar*Tests`.
@Suite struct CommandBarSmokeTests {
    /// The Home tile, the Settings page and the migrated switch all reach the bar through the tab id `commandbar`.
    @Test @MainActor func tabHasStableIdentity() {
        let tab = CommandBarFeature.tab()
        #expect(tab.id == "commandbar")
        #expect(tab.title == "Commandes")
        #expect(tab.systemImage == "command")
    }

    @Test func aBarCommandKeepsWhatTheShellGaveIt() {
        let command = BarCommand(id: "island.tab.dock", title: "Ouvrir Dock", keywords: ["île", "dock"]) {}
        #expect(command.id == "island.tab.dock" && command.title == "Ouvrir Dock" && command.keywords == ["île", "dock"])
        #expect(BarCommand(id: "x", title: "X") {}.keywords.isEmpty)
    }

    /// Nothing is bound in a test process: the registry does not let the bar run, so the button answers false and
    /// opens nothing (the caller then says why).
    @Test @MainActor func theButtonOpensNothingWhileTheRegistryHoldsTheBarDown() {
        #expect(CommandBarFeature.show() == false)
    }
}
