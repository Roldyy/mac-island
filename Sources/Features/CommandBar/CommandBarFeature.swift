import Foundation
import IslandKit
import SwiftUI

public enum CommandBarFeature {
    /// `~/Library/Application Support/be.roldy.macisland/Data`, shared with the other features.
    static var dataDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("be.roldy.macisland", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
    }

    @MainActor static let registry = CommandRegistry()

    /// Created on first use, so building the tab list touches nothing on disk.
    @MainActor static let shared: CommandBarController = {
        let habits = HabitStore(directory: dataDirectory)
        let reg = registry
        let sources: [any ResultSource] = [
            CalculatorSource(), AppSource(), FileSource(), CommandSource(registry: reg), WebSearchSource(),
        ]
        var actions = BarActions.live
        actions.runCommand = { reg.run(id: $0) }
        let model = CommandBarModel(sources: sources, habits: habits, actions: actions)
        return CommandBarController(settings: CommandBarSettings(), registrar: CommandBarHotkeyService(),
                                    presenter: CommandBarPanelPresenter(model: model), habits: habits)
    }()

    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "commandbar", title: "Commandes", systemImage: "command") {
            AnyView(CommandBarSettingsView(controller: shared))
        }
    }

    /// Extension point: the shell hands commands from other features to the bar.
    /// A command with an id already registered replaces the earlier one.
    @MainActor public static func register(commands: [BarCommand]) { registry.register(commands) }

    /// Register the global hotkey (when enabled in the settings). Idempotent.
    @MainActor public static func start() { shared.start() }

    /// Unregister the hotkey and close the panel. Idempotent.
    @MainActor public static func stop() { shared.stop() }
}
