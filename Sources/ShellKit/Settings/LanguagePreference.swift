import Foundation

/// The language the user picked. Only French text exists today: the choice is stored so the translations
/// that come later find it, and the page says so.
public enum LanguagePreference: String, CaseIterable, Identifiable, Sendable {
    case french = "fr", english = "en", dutch = "nl"

    public static let key = "appLanguage"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .french: "Français"
        case .english: "English"
        case .dutch: "Nederlands"
        }
    }

    public var isTranslated: Bool { self == .french }

    public static func load(from defaults: UserDefaults) -> LanguagePreference {
        defaults.string(forKey: key).flatMap(LanguagePreference.init(rawValue:)) ?? .french
    }

    public func save(to defaults: UserDefaults) { defaults.set(rawValue, forKey: Self.key) }
}
