import IslandKit

/// Preset sets of switches offered at the top of the Settings window.
public enum FeatureBundle: String, CaseIterable, Identifiable, Sendable {
    case essentiel, productivite, tout

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .essentiel: "Essentiel"
        case .productivite: "Productivité"
        case .tout: "Tout"
        }
    }

    private static let essential: Set<String> = ["terminal", "agents", "clipboard", "nowplaying", "keepawake", "monitor"]
    private static let productivity: Set<String> = essential.union(["shelf", "commandbar", "finder", "dock", "audio"])

    /// Ids switched on by the bundle; every other feature of `descriptors` is switched off.
    public func ids(in descriptors: [FeatureDescriptor]) -> Set<String> {
        let all = Set(descriptors.map(\.id))
        switch self {
        case .essentiel: return all.intersection(Self.essential)
        case .productivite: return all.intersection(Self.productivity)
        case .tout: return all
        }
    }
}
