import Foundation

/// One row noted from a reference page. Parsed from a one-line DSL (`K|label|extra|extra`).
public struct SettingsItem: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case heading = "H"
        case caption = "L"
        case toggle = "T"
        /// A menu with a current value.
        case menu = "P"
        /// A group of choices (segmented control or radio group).
        case choices = "S"
        case slider = "D"
        case field = "F"
        case stepper = "N"
        case button = "B"
        case link = "K"
    }

    public let kind: Kind
    public let label: String
    /// Menu: the current value. Slider: the stored value. Choices: the selected option.
    public let value: String
    public let options: [String]

    public init(kind: Kind, label: String, value: String = "", options: [String] = []) {
        self.kind = kind
        self.label = label
        self.value = value
        self.options = options
    }

    public static func parse(_ line: String) -> SettingsItem? {
        let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard let first = parts.first, let kind = Kind(rawValue: first), parts.count >= 2 else { return nil }
        switch kind {
        case .choices:
            guard parts.count >= 3 else { return nil }
            let options = parts[2].split(separator: ";").map(String.init)
            return SettingsItem(kind: kind, label: parts[1], value: parts.count > 3 ? parts[3] : "", options: options)
        case .menu, .slider:
            return SettingsItem(kind: kind, label: parts[1], value: parts.count > 2 ? parts[2] : "")
        default:
            return SettingsItem(kind: kind, label: parts[1])
        }
    }

    /// A card of related rows: a heading (may be empty) and what follows it.
    public struct Block: Equatable, Sendable {
        public let title: String
        public let items: [SettingsItem]
    }

    /// Splits a flat list into blocks at each heading, drops a caption that only repeats the label of the
    /// control after it, and drops blocks with nothing in them.
    public static func blocks(_ items: [SettingsItem]) -> [Block] {
        var blocks: [Block] = []
        var title = ""
        var current: [SettingsItem] = []
        func flush() {
            if !current.isEmpty { blocks.append(Block(title: title, items: current)) }
            current = []
        }
        for (index, item) in items.enumerated() {
            if item.kind == .heading {
                flush()
                title = item.label
                continue
            }
            if item.kind == .caption, index + 1 < items.count, items[index + 1].label == item.label { continue }
            current.append(item)
        }
        flush()
        return blocks
    }
}

/// The rows of every page, merged from the nine section tables.
public enum SettingsPageContent {
    public static let all: [String: [String]] = [
        essentials, utilities, sound, energy, windows, input, files, apps, app,
    ].reduce(into: [:]) { $0.merge($1) { first, _ in first } }

    public static func items(for pageID: String) -> [SettingsItem] {
        (all[pageID] ?? []).compactMap(SettingsItem.parse)
    }
}
