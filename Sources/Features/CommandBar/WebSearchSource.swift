import Foundation

/// Fallback row: opens the default browser on a search page. The query is percent-encoded and
/// capped; it is only ever placed in the `q` parameter.
struct WebSearchSource: ResultSource {
    let sourceID = "web"
    static let maxQueryLength = 200

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func url(for query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = String(trimmed.prefix(maxQueryLength))
                .addingPercentEncoding(withAllowedCharacters: unreserved) else { return nil }
        return URL(string: "https://duckduckgo.com/?q=" + encoded)
    }

    func results(for query: String) async -> [BarResult] {
        guard let url = Self.url(for: query) else { return [] }
        return [BarResult(id: "web", title: "Rechercher sur le web", subtitle: "Ouvre le navigateur par d\u{00E9}faut",
                          kind: .web, action: .open(url), fixedScore: -1000)]
    }
}
