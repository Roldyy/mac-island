import Foundation

/// Usage counter per result id, with exponential decay. Stores ids, counts and last-use dates only:
/// the typed query text never reaches this type. File: `<directory>/CommandBarHabits.json` (0600).
@MainActor
final class HabitStore {
    struct Entry: Codable, Equatable {
        var count: Double
        var last: Date
    }

    private struct Payload: Codable {
        var version = 1
        var entries: [String: Entry]
    }

    static let fileName = "CommandBarHabits.json"
    static let pruneBelow = 0.05

    let fileURL: URL
    private let halfLifeDays: Double
    private var entries: [String: Entry] = [:]

    init(directory: URL, halfLifeDays: Double = 30) {
        self.fileURL = directory.appendingPathComponent(Self.fileName)
        self.halfLifeDays = halfLifeDays
        load()
    }

    private func decayed(_ e: Entry, at now: Date) -> Double {
        let days = max(0, now.timeIntervalSince(e.last)) / 86_400
        return e.count * pow(0.5, days / halfLifeDays)
    }

    func weight(_ id: String, now: Date = Date()) -> Double {
        entries[id].map { decayed($0, at: now) } ?? 0
    }

    func lastUsed(_ id: String) -> Date? { entries[id]?.last }

    func weights(now: Date = Date()) -> HabitWeights {
        HabitWeights(weight: { [weak self] id in MainActor.assumeIsolated { self?.weight(id, now: now) ?? 0 } },
                     lastUsed: { [weak self] id in MainActor.assumeIsolated { self?.lastUsed(id) } })
    }

    func topIDs(limit: Int, now: Date = Date()) -> [String] {
        entries.map { ($0.key, decayed($0.value, at: now)) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
            .prefix(limit).map(\.0)
    }

    func record(_ id: String, now: Date = Date()) {
        let current = entries[id].map { decayed($0, at: now) } ?? 0
        entries[id] = Entry(count: current + 1, last: now)
        for (key, e) in entries where decayed(e, at: now) < Self.pruneBelow { entries[key] = nil }
        save()
    }

    /// Forget everything, in memory and on disk.
    func clear() {
        entries = [:]
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        // A corrupt file is a cold start, never a crash and never an error shown.
        guard let payload = try? decoder.decode(Payload.self, from: data) else { return }
        entries = payload.entries
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(Payload(entries: entries)) else { return }
        try? PrivateFiles.writeAtomic(data, to: fileURL)
    }
}
