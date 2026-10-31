import Foundation

/// Pure filtering of the sidebar. Matching ignores case and accents; every word of the query must match.
public enum SettingsSearch {
    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
    }

    /// How well a page answers a query: 0 = no match, higher = better (title match beats keyword match).
    public static func score(_ page: SettingsPage, query: String) -> Int {
        let words = fold(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return 1 }
        let title = fold(page.title)
        let rest = fold(([page.section.title, page.summary] + page.keywords).joined(separator: " "))
        var total = 0
        for word in words {
            if title == word { total += 100 } else if title.contains(word) { total += 10 } else if rest.contains(word) { total += 1 } else { return 0 }
        }
        return total
    }

    /// Pages in sidebar order when the query is empty, else matching pages, best first (stable among equals).
    public static func filter(_ pages: [SettingsPage], query: String) -> [SettingsPage] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return pages }
        return pages.enumerated()
            .map { (offset: $0.offset, page: $0.element, score: score($0.element, query: trimmed)) }
            .filter { $0.score > 0 }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }
            .map(\.page)
    }

    /// The sidebar when no query is typed: sections with their pages, empty sections dropped.
    public static func sections(_ pages: [SettingsPage]) -> [(section: SettingsSection, pages: [SettingsPage])] {
        SettingsSection.allCases.compactMap { section in
            let rows = pages.filter { $0.section == section }
            return rows.isEmpty ? nil : (section, rows)
        }
    }
}
