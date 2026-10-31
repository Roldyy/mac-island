import IslandUI

/// Text and status the hub shows next to a feature. Pure, so every state has a tested wording.
public struct FeatureBadge: Equatable {
    public let text: String
    public let status: IslandStatus

    public init(_ state: FeatureState) {
        switch state {
        case .active: self = .init("Prêt", .success)
        case .needsPermission(let p): self = .init("Autorisation requise : \(p.title)", .warning)
        case .off: self = .init("Désactivé", .neutral)
        case .killed: self = .init("Coupé par l'interrupteur général", .danger)
        case .safeMode: self = .init("Désactivé en mode sans échec", .warning)
        case .quarantined: self = .init("En quarantaine après 2 plantages", .danger)
        case .unavailable(let reason): self = .init(reason, .neutral)
        }
    }

    private init(_ text: String, _ status: IslandStatus) {
        self.text = text
        self.status = status
    }
}
