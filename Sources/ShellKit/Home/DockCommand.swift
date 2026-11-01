import Foundation
import IslandKit

/// Where a command sits in the picker.
public enum DockCategory: String, CaseIterable, Codable, Sendable {
    case panels, capture, tools, system, features, settings

    public var title: String {
        switch self {
        case .panels: "Panneaux"
        case .capture: "Capture"
        case .tools: "Outils"
        case .system: "Système"
        case .features: "Fonctions"
        case .settings: "Réglages"
        }
    }
}

/// One command of the app the extra dock can run: the single catalog entry (id, French title, symbol, availability,
/// run closure). Built by `ShellContext.dockCatalog()` from what exists at that moment.
public struct DockCommand: Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    /// Icon while a toggle is on.
    public let activeSystemImage: String?
    public let category: DockCategory
    /// Extra words the picker's search matches (English names, synonyms).
    public let keywords: [String]
    /// The registry feature that must be on. Nil when the command needs no feature.
    public let featureID: String?
    /// Non-nil: the command changes or discards something, so the dock asks this question first and the command
    /// runs only after the "Confirmer" click. Nothing destructive may leave it nil (a test pins the catalog).
    public let confirmation: String?
    public let run: @MainActor () -> Void
    /// A toggle reports whether it is on; read inside the view's body so the button follows it.
    public let isOn: (@MainActor () -> Bool)?
    /// Why the command cannot run right now (permission, panel off, nothing registered), nil when it can.
    public let unavailableReason: (@MainActor () -> String?)?

    public init(id: String, title: String, systemImage: String, activeSystemImage: String? = nil,
                category: DockCategory, keywords: [String] = [], featureID: String? = nil,
                confirmation: String? = nil, isOn: (@MainActor () -> Bool)? = nil,
                unavailableReason: (@MainActor () -> String?)? = nil, run: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.activeSystemImage = activeSystemImage
        self.category = category
        self.keywords = keywords
        self.featureID = featureID
        self.confirmation = confirmation
        self.isOn = isOn
        self.unavailableReason = unavailableReason
        self.run = run
    }

    public var needsConfirmation: Bool { confirmation != nil }
}

/// Whether a command can run, and if not, the one French line that says why (the button's tooltip).
public enum DockAvailability: Equatable, Sendable {
    case available
    case disabled(reason: String)

    public var isAvailable: Bool { self == .available }
    public var reason: String? {
        if case .disabled(let reason) = self { return reason }
        return nil
    }
}

/// The disabled-state rules, pure: the registry's verdict for the command's feature first, then the command's own reason.
public enum DockAvailabilityRules {
    public static func evaluate(featureTitle: String?, featureState: FeatureState?, ownReason: String?) -> DockAvailability {
        if let featureState {
            let name = featureTitle.map { "« \($0) »" } ?? "Cette fonction"
            switch featureState {
            case .active: break
            case .needsPermission(let permission):
                return .disabled(reason: "\(name) attend une autorisation (\(permission.rawValue)). Ouvre les Réglages pour l'accorder.")
            case .off: return .disabled(reason: "\(name) est désactivée. Active-la dans Fonctionnalités.")
            case .killed: return .disabled(reason: "Tout est coupé par l'interrupteur général.")
            case .safeMode: return .disabled(reason: "Mode sans échec : \(name) est suspendue.")
            case .quarantined: return .disabled(reason: "\(name) a été mise en quarantaine après deux démarrages ratés.")
            case .unavailable(let reason): return .disabled(reason: reason)
            }
        }
        if let ownReason, !ownReason.isEmpty { return .disabled(reason: ownReason) }
        return .available
    }
}
