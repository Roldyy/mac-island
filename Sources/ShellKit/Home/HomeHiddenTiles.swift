import Foundation

/// The set of tile ids the user hid from the home, stored as a JSON array of strings (`notchHomeHiddenTiles`).
enum HomeHiddenTiles {
    /// Anything unreadable gives an empty set: a damaged value never hides the whole grid.
    static func decode(_ stored: Any?) -> Set<String> {
        let data: Data?
        switch stored {
        case let value as Data: data = value
        case let value as String: data = value.data(using: .utf8)
        default: data = nil
        }
        guard let data, let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(ids)
    }

    /// Sorted, so the stored value does not change when nothing did.
    static func encode(_ ids: Set<String>) -> Data {
        (try? JSONEncoder().encode(ids.sorted())) ?? Data("[]".utf8)
    }
}
