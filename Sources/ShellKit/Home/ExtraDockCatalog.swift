import Foundation

/// Commands the app registers at launch: the ones whose entry points live in code ShellKit does not see (the ported
/// capture, recorder, OCR, colour picker, mic mute...). A command registered twice keeps the latest.
@MainActor
public final class DockCommandRegistry {
    public private(set) var commands: [DockCommand] = []

    public init() {}

    public func register(_ command: DockCommand) {
        commands.removeAll { $0.id == command.id }
        commands.append(command)
    }

    public func register(_ list: [DockCommand]) { list.forEach(register) }
}

/// Pure helpers over a list of commands: one catalog, no repeated id, a search that ignores case and accents.
public enum ExtraDockCatalog {
    /// Commands in their given order, the first of each id wins (the core catalog beats an app registration).
    public static func unique(_ commands: [DockCommand]) -> [DockCommand] {
        var seen = Set<String>()
        return commands.filter { seen.insert($0.id).inserted }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
    }

    /// Every word of the query must appear in the title, a keyword or the category name.
    public static func search(_ commands: [DockCommand], query: String) -> [DockCommand] {
        let words = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return commands }
        return commands.filter { command in
            let haystack = fold(([command.title, command.category.title] + command.keywords).joined(separator: " "))
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    /// The picker's sections: category order, then the command order inside each. Empty sections are left out.
    public static func grouped(_ commands: [DockCommand]) -> [(category: DockCategory, commands: [DockCommand])] {
        DockCategory.allCases.compactMap { category in
            let inside = commands.filter { $0.category == category }
            return inside.isEmpty ? nil : (category, inside)
        }
    }
}
