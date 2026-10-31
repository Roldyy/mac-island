import Foundation

/// The catalog folded and grouped once. Typing in the search field used to re-fold every title, summary
/// and keyword of the 67 pages on every keystroke; the folded text now lives here, built on first use.
public final class SettingsSearchIndex: Sendable {
    public static let shared = SettingsSearchIndex(pages: SettingsPageCatalog.all)

    /// How many indexes were built in this process (a test pins the shared one at one).
    nonisolated(unsafe) public private(set) static var buildCount = 0

    private struct Entry: Sendable {
        let page: SettingsPage
        let title: String
        let rest: String
    }

    private let entries: [Entry]
    /// Sections with their pages, empty sections dropped: the sidebar when no query is typed.
    public let sections: [(section: SettingsSection, pages: [SettingsPage])]
    public let pages: [SettingsPage]

    public init(pages: [SettingsPage]) {
        Self.buildCount += 1
        self.pages = pages
        entries = pages.map {
            Entry(page: $0, title: SettingsSearch.fold($0.title),
                  rest: SettingsSearch.fold(([$0.section.title, $0.summary] + $0.keywords).joined(separator: " ")))
        }
        sections = SettingsSearch.sections(pages)
    }

    /// Same result as `SettingsSearch.filter`, without folding the catalog again.
    public func filter(query: String) -> [SettingsPage] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return pages }
        let words = SettingsSearch.fold(trimmed).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return pages }
        return entries.enumerated()
            .compactMap { offset, entry -> (Int, Int, SettingsPage)? in
                var total = 0
                for word in words {
                    if entry.title == word { total += 100 } else if entry.title.contains(word) { total += 10 } else if entry.rest.contains(word) { total += 1 } else { return nil }
                }
                return (total, offset, entry.page)
            }
            .sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }
            .map(\.2)
    }
}
