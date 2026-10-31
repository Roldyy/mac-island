import Foundation

/// The stack colors of the trend chart: one per model family, so the legend stays at four entries.
enum ModelFamily: Int, CaseIterable, Comparable, Sendable {
    case opus, sonnet, haiku, other

    init(model: String) {
        let name = model.lowercased()
        if name.contains("opus") { self = .opus }
        else if name.contains("sonnet") { self = .sonnet }
        else if name.contains("haiku") { self = .haiku }
        else { self = .other }
    }

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .opus: "Opus"
        case .sonnet: "Sonnet"
        case .haiku: "Haiku"
        case .other: "Autres"
        }
    }
}

extension ModelFamily {
    /// "claude-sonnet-4-5-20250929" -> "Sonnet 4.5". Anything unrecognised is shown as logged.
    static func displayName(_ model: String) -> String {
        var parts = model.split(separator: "-").map(String.init)
        if parts.first?.lowercased() == "claude" { parts.removeFirst() }
        if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) { parts.removeLast() }
        let words = parts.filter { $0.allSatisfy(\.isLetter) }
        let numbers = parts.filter { $0.allSatisfy(\.isNumber) }
        guard words.count == 1, parts.count == words.count + numbers.count, !numbers.isEmpty else { return model }
        return "\(words[0].capitalized) \(numbers.joined(separator: "."))"
    }
}

/// One slice of a trend bar.
struct FamilyShare: Equatable, Sendable {
    var family: ModelFamily
    var tokens: Int
    var cost: Double
}
