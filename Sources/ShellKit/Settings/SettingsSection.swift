import Foundation

/// The nine groups of the sidebar, in display order.
public enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case essentials, utilities, sound, energy, windows, input, files, apps, app

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .essentials: "Essentiel"
        case .utilities: "Utilitaires"
        case .sound: "Son"
        case .energy: "Énergie et écran"
        case .windows: "Fenêtres et Dock"
        case .input: "Souris et clavier"
        case .files: "Fichiers"
        case .apps: "Gestion des apps"
        case .app: "App"
        }
    }
}
