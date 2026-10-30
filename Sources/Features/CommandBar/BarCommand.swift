import Foundation

/// A command another feature hands to the bar through `CommandBarFeature.register(commands:)`.
public struct BarCommand {
    public let id: String
    public let title: String
    public let keywords: [String]
    public let run: @MainActor () -> Void

    public init(id: String, title: String, keywords: [String] = [], run: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.keywords = keywords
        self.run = run
    }
}

/// Commands registered by the shell. Same id replaces the earlier command.
@MainActor
final class CommandRegistry {
    private(set) var commands: [BarCommand] = []

    func register(_ new: [BarCommand]) {
        for c in new {
            if let i = commands.firstIndex(where: { $0.id == c.id }) { commands[i] = c } else { commands.append(c) }
        }
    }

    func run(id: String) {
        commands.first { $0.id == id }?.run()
    }
}

@MainActor
struct CommandSource: ResultSource {
    nonisolated let sourceID = "commands"
    let registry: CommandRegistry

    func results(for query: String) async -> [BarResult] {
        registry.commands.map {
            BarResult(id: "cmd:\($0.id)", title: $0.title, subtitle: "Commande", kind: .command,
                      action: .runCommand($0.id), keywords: $0.keywords)
        }
    }
}
