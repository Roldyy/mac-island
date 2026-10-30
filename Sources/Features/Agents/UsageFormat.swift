import Foundation

enum UsageFormat {
    static func tokens(_ n: Int) -> String {
        switch n {
        case 1_000_000_000...: return String(format: "%.1fB", Double(n) / 1e9)
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1e6)
        case 1_000...: return String(format: "%.1fK", Double(n) / 1e3)
        default: return "\(n)"
        }
    }

    static func cost(_ value: Double, estimated: Bool) -> String {
        (estimated ? "~" : "") + value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }
}
