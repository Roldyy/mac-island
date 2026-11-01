import Foundation
import PortKit
import ShellKit

/// Hands the ported features' commands to the island's extra dock. The shell core already lists panels, features,
/// Settings pages and quick actions; this adds what only PortKit can reach (capture, recorder, OCR, colour picker,
/// plain paste, mic mute, launcher, radial menu, clipboard, timer), each through the service's own door.
@MainActor
enum ExtraDockWiring {
    /// Registers every `PortDockCommands` entry. A command that acts on the screen or on another app closes the
    /// island first and runs once the closing animation is done (so the island is not in the shot, and the focus is back).
    static func install(into registry: DockCommandRegistry, closeIsland: @escaping @MainActor () -> Void) {
        registry.register(PortDockCommands.all().map { command in
            DockCommand(
                id: command.id, title: command.title, systemImage: command.systemImage,
                category: category(command.category), keywords: command.keywords,
                confirmation: command.confirmation, isOn: command.isOn,
                unavailableReason: command.unavailableReason) {
                    guard command.closesIsland else { command.run(); return }
                    closeIsland()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        command.run()
                    }
                }
        })
    }

    static func category(_ category: PortDockCommand.Category) -> DockCategory {
        switch category {
        case .capture: .capture
        case .tools: .tools
        case .system: .system
        }
    }
}
