import Foundation

/// One row of the palette. Ids are stable (`app:<path>`, `file:<path>`, `cmd:<id>`, `calc`, `web`)
/// so habits can key on them; the typed query is never part of a result or stored anywhere.
struct BarResult: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case app, file, command, calculator, web }

    enum Action: Equatable, Sendable {
        case open(URL)             // NSWorkspace, with a URL the app found itself
        case copy(String)          // calculator result to the pasteboard
        case runCommand(String)    // id of a registered BarCommand
    }

    let id: String
    var title: String
    var subtitle: String
    var kind: Kind
    var action: Action
    var keywords: [String]
    /// Pins a row regardless of the query: calculator on top, web fallback at the bottom.
    var fixedScore: Double?
    /// What Cmd+Enter shows in Finder, when there is something to show.
    var reveal: URL?

    init(id: String, title: String, subtitle: String = "", kind: Kind, action: Action,
         keywords: [String] = [], fixedScore: Double? = nil, reveal: URL? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.action = action
        self.keywords = keywords
        self.fixedScore = fixedScore
        self.reveal = reveal
    }

    /// Only apps and commands feed habits: no file paths, no calculator or web noise.
    var tracksHabit: Bool { kind == .app || kind == .command }
}
