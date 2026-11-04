import Foundation

/// Reads and writes the journal in defaults. Every mutation reads the stored value first (one writer, no cache), so
/// the guard, the apply and the undo can never overwrite each other with a stale copy.
public final class DefaultAppsJournalStore: @unchecked Sendable {
    public static let key = "defaultAppsJournal"
    /// A journal that could not be decoded is copied here once before an empty one replaces it.
    public static let backupKey = "defaultAppsJournal.corrupt"

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func load() -> JournalLoad {
        lock.lock(); defer { lock.unlock() }
        return loadLocked()
    }

    public var entries: [JournalEntry] {
        if case .journal(let journal) = load() { return journal.entries }
        return []
    }

    /// Writes the entry. False when the journal cannot be written (newer version, or too big): the caller must then
    /// change nothing.
    @discardableResult
    public func append(_ entry: JournalEntry) -> Bool {
        mutate { journal in
            journal.entries.append(entry)
            // The first known handler of a type is kept for good.
            for change in entry.changes where journal.originals[change.key] == nil {
                if let previous = change.previousBundleID { journal.originals[change.key] = previous }
            }
        }
    }

    /// The original handler of every type this feature ever changed (see `DefaultAppsJournal.originals`).
    public var originals: [String: String] {
        if case .journal(let journal) = load() { return journal.originals }
        return [:]
    }

    /// Sets the state of one change of one entry.
    @discardableResult
    public func mark(entry id: UUID, key: String, state: ChangeState) -> Bool {
        mutate { journal in
            guard let e = journal.entries.firstIndex(where: { $0.id == id }),
                  let c = journal.entries[e].changes.firstIndex(where: { $0.key == key }) else { return }
            journal.entries[e].changes[c].state = state
        }
    }

    /// Replaces the whole entry list (undo removes what it resolved).
    @discardableResult
    public func replaceEntries(_ entries: [JournalEntry]) -> Bool {
        mutate { $0.entries = entries }
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: Self.key)
    }

    private func loadLocked() -> JournalLoad {
        guard let text = defaults.string(forKey: Self.key) else { return .journal(DefaultAppsJournal()) }
        return JournalCodec.decode(text)
    }

    private func mutate(_ change: (inout DefaultAppsJournal) -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var journal: DefaultAppsJournal
        switch loadLocked() {
        case .journal(let stored): journal = stored
        case .unsupportedVersion: return false
        case .corrupt:
            if let raw = defaults.string(forKey: Self.key) { defaults.set(String(raw.prefix(JournalCodec.maxBytes)), forKey: Self.backupKey) }
            journal = DefaultAppsJournal()
        }
        change(&journal)
        guard let text = JournalCodec.encode(journal) else { return false }
        defaults.set(text, forKey: Self.key)
        return true
    }
}
