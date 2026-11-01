import Foundation

/// One page of the Settings window.
public struct SettingsPage: Identifiable, Equatable, Sendable {
    /// What fills the page.
    public enum Kind: Equatable, Sendable {
        case general, features, advanced, about, whatsNew, support
        /// Rows noted from the reference page; the ones with a live binding work, the others wait.
        case declarative
    }

    public let id: String
    public let title: String
    public let symbol: String
    public let section: SettingsSection
    /// One sentence, in our own words, under the title.
    public let summary: String
    public let keywords: [String]
    /// The registry feature this page belongs to, if any: the page then opens with its switch and status.
    public let featureID: String?
    public let kind: Kind

    public init(id: String, title: String, symbol: String, section: SettingsSection, summary: String,
                keywords: [String] = [], featureID: String? = nil, kind: Kind = .declarative) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.section = section
        self.summary = summary
        self.keywords = keywords
        self.featureID = featureID
        self.kind = kind
    }

    /// True when nothing on the page can be changed yet.
    public var isComingSoon: Bool {
        kind == .declarative && featureID == nil && SettingsLive.isEmpty(pageID: id)
            && !SettingsPageBodies.hasBody(for: id)
    }
}
