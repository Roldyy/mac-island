import Foundation
import IslandKit

public extension FeatureCategory {
    var title: String {
        switch self {
        case .daily: "Au quotidien"
        case .claude: "Claude et agents"
        case .input: "Clavier et souris"
        case .display: "Écran"
        case .sound: "Son"
        case .windows: "Fenêtres"
        case .capture: "Capture"
        case .island: "Île"
        case .monitor: "Surveillance"
        case .files: "Fichiers"
        case .tools: "Outils"
        case .apps: "Applications"
        case .media: "Médias"
        }
    }
}

public extension FeaturePermission {
    var title: String {
        switch self {
        case .accessibility: "Accessibilité"
        case .screenRecording: "Enregistrement de l'écran"
        case .automation: "Automatisation"
        case .audioCapture: "Capture audio"
        case .camera: "Caméra"
        case .microphone: "Micro"
        case .notifications: "Notifications"
        case .calendar: "Calendrier"
        case .bluetooth: "Bluetooth"
        case .fullDiskAccess: "Accès complet au disque"
        case .helperDaemon: "Assistant système"
        }
    }

    /// Pane of System Settings to open. The shell opens it; nothing here asks for the permission.
    var settingsURL: URL? {
        if let pane = privacyPane { return pane.url }
        switch self {
        case .notifications: return URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        case .helperDaemon: return URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        default: return nil
        }
    }
}

/// Pure grouping and search for the Settings list.
public enum FeatureHub {
    public struct Section: Equatable {
        public let category: FeatureCategory
        public let features: [FeatureDescriptor]
        public static func == (a: Section, b: Section) -> Bool {
            a.category == b.category && a.features.map(\.id) == b.features.map(\.id)
        }
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    public static func matches(_ d: FeatureDescriptor, query: String) -> Bool {
        let words = fold(query).split(separator: " ")
        guard !words.isEmpty else { return true }
        let haystack = fold([d.title, d.summary, d.category.title].joined(separator: " "))
        return words.allSatisfy { haystack.contains($0) }
    }

    /// Non-empty categories in `FeatureCategory` order, features in registry order.
    public static func sections(_ descriptors: [FeatureDescriptor], query: String) -> [Section] {
        FeatureCategory.allCases.compactMap { category in
            let rows = descriptors.filter { $0.category == category && matches($0, query: query) }
            return rows.isEmpty ? nil : Section(category: category, features: rows)
        }
    }
}
