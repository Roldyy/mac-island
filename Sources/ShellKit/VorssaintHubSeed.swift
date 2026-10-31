import Foundation
import IslandKit

/// Reads the old app's `featureHubKeptFeatures` value. Its stored shape was not observed, so every
/// plausible one is accepted: a delimited string, a list, JSON in a Data, or a name-to-flag dictionary (only `true` values count).
public enum VorssaintHubSeed {
    public static let key = "featureHubKeptFeatures"

    /// Old names seen as key prefixes in the old app's defaults, mapped to our feature ids.
    private static let aliases: [String: String] = [
        "mixer": "audio", "keepawake": "keepawake", "brightness": "display", "dockclick": "dock",
        "dockpreview": "dock", "commandbar": "commandbar",
    ]

    public static func tokens(in raw: Any?) -> [String] {
        switch raw {
        case let s as String:
            return s.split(whereSeparator: { ",;|\n\t ".contains($0) }).map(String.init)
        case let list as [Any]:
            return list.compactMap { $0 as? String }
        case let dict as [String: Any]:
            return dict.filter { isTrueBool($0.value) }.map(\.key)
        case let data as Data:
            guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
            return tokens(in: object)
        default:
            return []
        }
    }

    /// Only a real Boolean true keeps a feature: not 1, 2, "YES" or "NO".
    static func isTrueBool(_ value: Any) -> Bool {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
        return number.boolValue
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    public static func featureIDs(in raw: Any?, descriptors: [FeatureDescriptor]) -> Set<String> {
        var result = Set<String>()
        for token in tokens(in: raw) {
            let n = normalize(token)
            if let d = descriptors.first(where: { normalize($0.id) == n || normalize($0.title) == n }) {
                result.insert(d.id)
            } else if let id = aliases[n], descriptors.contains(where: { $0.id == id }) {
                result.insert(id)
            }
        }
        return result
    }
}
