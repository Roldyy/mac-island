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

/// One slice of a trend bar.
struct FamilyShare: Equatable, Sendable {
    var family: ModelFamily
    var tokens: Int
    var cost: Double
}
