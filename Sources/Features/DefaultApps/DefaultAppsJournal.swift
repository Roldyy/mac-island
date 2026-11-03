import Foundation

public enum ChangeState: String, Codable, Sendable {
    /// Written before the call: the outcome is unknown (a crash can leave it so).
    case planned
    case applied
    /// macOS answered without changing the value we read back. Still undoable (undo checks the live value).
    case unverified
    /// The call returned an error: nothing changed, nothing to undo.
    case failed
}

/// One type or scheme of one replacement, with the handler it had before.
public struct JournalChange: Codable, Equatable, Sendable {
    public var kind: ChangeKind
    public var identifier: String
    /// Bundle id of the previous handler, nil when none was known.
    public var previousBundleID: String?
    public var state: ChangeState

    public init(kind: ChangeKind, identifier: String, previousBundleID: String?, state: ChangeState = .planned) {
        self.kind = kind
        self.identifier = identifier
        self.previousBundleID = previousBundleID
        self.state = state
    }

    public var key: String { "\(kind.rawValue):\(identifier)" }
}

/// One "Remplacer" click.
public struct JournalEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var replacementBundleID: String
    public var replacementName: String
    public var sourceName: String?
    public var changes: [JournalChange]

    public init(id: UUID = UUID(), date: Date, replacementBundleID: String, replacementName: String,
                sourceName: String?, changes: [JournalChange]) {
        self.id = id
        self.date = date
        self.replacementBundleID = replacementBundleID
        self.replacementName = replacementName
        self.sourceName = sourceName
        self.changes = changes
    }
}

/// The versioned journal kept in defaults under `defaultAppsJournal` (a JSON string, oldest entry first).
public struct DefaultAppsJournal: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var version: Int
    public var entries: [JournalEntry]

    public init(version: Int = DefaultAppsJournal.currentVersion, entries: [JournalEntry] = []) {
        self.version = version
        self.entries = entries
    }
}

public enum JournalLoad: Equatable, Sendable {
    case journal(DefaultAppsJournal)
    /// Stored by a newer app version: read-only, never overwritten.
    case unsupportedVersion(Int)
    /// Not decodable (or over the size cap): kept aside, an empty journal is used.
    case corrupt
}

/// Encode and decode with the size caps. Pure.
public enum JournalCodec {
    public static let maxEntries = 30
    public static let maxChangesPerEntry = 500
    public static let maxBytes = 256 * 1024

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// Caps the journal (oldest entries go first until it fits) and returns its JSON, nil when even one entry is too big.
    public static func encode(_ journal: DefaultAppsJournal) -> String? {
        var capped = journal
        capped.entries = capped.entries.suffix(maxEntries).map { entry in
            var entry = entry
            entry.changes = Array(entry.changes.prefix(maxChangesPerEntry))
            return entry
        }
        while true {
            guard let data = try? encoder().encode(capped) else { return nil }
            if data.count <= maxBytes { return String(data: data, encoding: .utf8) }
            if capped.entries.count <= 1 { return nil }
            capped.entries.removeFirst()
        }
    }

    public static func decode(_ text: String) -> JournalLoad {
        guard text.utf8.count <= maxBytes * 2, let data = text.data(using: .utf8) else { return .corrupt }
        struct Header: Decodable { let version: Int }
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else { return .corrupt }
        guard header.version <= DefaultAppsJournal.currentVersion else { return .unsupportedVersion(header.version) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let journal = try? decoder.decode(DefaultAppsJournal.self, from: data) else { return .corrupt }
        return .journal(journal)
    }
}
