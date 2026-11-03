import Foundation

/// A replacement the user applied and that the guard may re-apply.
public struct StoredChoice: Codable, Equatable, Sendable {
    public var kind: ChangeKind
    public var identifier: String
    public var bundleID: String
    /// The user picked this protected item on purpose.
    public var explicitlyPicked: Bool

    public init(kind: ChangeKind, identifier: String, bundleID: String, explicitlyPicked: Bool) {
        self.kind = kind
        self.identifier = identifier
        self.bundleID = bundleID
        self.explicitlyPicked = explicitlyPicked
    }

    public var key: String { "\(kind.rawValue):\(identifier)" }
}

struct ChoicesFile: Codable, Equatable {
    var version: Int
    var choices: [StoredChoice]
}

/// The stored choices (`defaultAppsChoices`, versioned JSON string, capped) and the per-type time of the guard's
/// last attempt (`defaultAppsGuardLast`). Both are this Mac's state: never part of a settings backup.
public final class DefaultAppsChoicesStore: @unchecked Sendable {
    public static let key = "defaultAppsChoices"
    public static let lastKey = "defaultAppsGuardLast"
    public static let maxChoices = 500
    static let maxBytes = 256 * 1024

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public var choices: [StoredChoice] {
        lock.lock(); defer { lock.unlock() }
        return loadLocked()
    }

    /// Records or replaces the choice for one type or scheme.
    public func upsert(_ choice: StoredChoice) {
        mutate { list in
            list.removeAll { $0.key == choice.key }
            list.append(choice)
            if list.count > Self.maxChoices { list.removeFirst(list.count - Self.maxChoices) }
        }
    }

    public func remove(keys: Set<String>) {
        mutate { $0.removeAll { keys.contains($0.key) } }
    }

    public func removeAll() {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: Self.key)
    }

    // MARK: guard timestamps

    public func lastAttempt(for key: String) -> Date? {
        lock.lock(); defer { lock.unlock() }
        let table = defaults.dictionary(forKey: Self.lastKey) as? [String: Double] ?? [:]
        return table[key].map { Date(timeIntervalSince1970: $0) }
    }

    /// Written BEFORE the attempt, so a failing type is also tried at most once per window.
    public func noteAttempt(for key: String, at date: Date) {
        lock.lock(); defer { lock.unlock() }
        var table = defaults.dictionary(forKey: Self.lastKey) as? [String: Double] ?? [:]
        table[key] = date.timeIntervalSince1970
        if table.count > Self.maxChoices {
            for old in table.sorted(by: { $0.value < $1.value }).prefix(table.count - Self.maxChoices) { table[old.key] = nil }
        }
        defaults.set(table, forKey: Self.lastKey)
    }

    // MARK: storage

    private func loadLocked() -> [StoredChoice] {
        guard let text = defaults.string(forKey: Self.key), text.utf8.count <= Self.maxBytes * 2,
              let data = text.data(using: .utf8),
              let file = try? JSONDecoder().decode(ChoicesFile.self, from: data),
              file.version == 1 else { return [] }
        return Array(file.choices.prefix(Self.maxChoices))
    }

    private func mutate(_ change: (inout [StoredChoice]) -> Void) {
        lock.lock(); defer { lock.unlock() }
        var list = loadLocked()
        change(&list)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(ChoicesFile(version: 1, choices: list)), data.count <= Self.maxBytes,
              let text = String(data: data, encoding: .utf8) else { return }
        defaults.set(text, forKey: Self.key)
    }
}
