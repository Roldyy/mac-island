import Foundation

/// The last colours picked with the eyedropper, newest first, without duplicates, capped. Pure value type;
/// `save(to:)` / `load(from:)` keep it in the app's defaults (a list of "#RRGGBB" strings, nothing else).
struct RecentColours: Equatable, Sendable {
    static let capacity = 12
    static let defaultsKey = "islandextras.colors.recent"

    private(set) var hexes: [String]

    init(_ hexes: [String] = []) {
        self.hexes = []
        for hex in hexes.reversed() { add(hex) }
    }

    /// "#RRGGBB", uppercase, with or without the leading "#". Nil for anything else.
    static func normalised(_ text: String) -> String? {
        let body = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard body.count == 6, body.allSatisfy(\.isHexDigit), body.allSatisfy(\.isASCII) else { return nil }
        return "#" + body.uppercased()
    }

    /// Components in 0...1 (clamped), rounded to the nearest 8-bit step.
    static func hex(red: Double, green: Double, blue: Double) -> String {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    mutating func add(_ hex: String) {
        guard let value = Self.normalised(hex) else { return }
        hexes.removeAll { $0 == value }
        hexes.insert(value, at: 0)
        if hexes.count > Self.capacity { hexes.removeLast(hexes.count - Self.capacity) }
    }

    func save(to defaults: UserDefaults) { defaults.set(hexes, forKey: Self.defaultsKey) }

    static func load(from defaults: UserDefaults) -> RecentColours {
        let stored = defaults.array(forKey: defaultsKey) ?? []
        return RecentColours(stored.compactMap { $0 as? String })
    }
}
