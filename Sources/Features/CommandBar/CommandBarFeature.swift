import IslandKit
import PortKit

/// The command bar is the ported Vorssaint one now (`PortKit/Bridge/CommandBar.swift`): this target only keeps what
/// the shell already calls by name. The tab id `commandbar` (the Home tile, the Settings page and the migrated switch
/// all point at it), the commands the shell hands to the bar, and the button that opens it. The registry starts and
/// stops the bar through `PortFeatureBinding`, not through this type, and the global shortcut belongs to the ported
/// service alone.
public enum CommandBarFeature {
    @MainActor public static func tab() -> IslandTab { PortCommandBar.tab() }

    /// Extension point: the shell hands commands from other features to the bar.
    /// A command with an id already registered replaces the earlier one.
    @MainActor public static func register(commands: [BarCommand]) {
        PortCommandBar.registerHostCommands(commands.map { command in
            PortCommandBar.HostCommand(id: command.id, title: command.title, keywords: command.keywords,
                                       run: command.run)
        })
    }

    /// Opens the bar now (Home tile, round button). False when the feature is off, killed or in safe mode:
    /// nothing opened. The caller closes the island first.
    @MainActor @discardableResult public static func show() -> Bool { PortCommandBar.show() }
}
