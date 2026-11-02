import Foundation

/// The imported profiles (10 at most, newest first) and which one is active. Pure value: no I/O.
struct TerminalProfileLibrary: Equatable, Sendable {
    static let maxProfiles = 10

    private(set) var profiles: [TerminalColorProfile] = []
    private(set) var activeID: UUID?

    init(profiles: [TerminalColorProfile] = [], activeID: UUID? = nil) {
        self.profiles = Array(profiles.prefix(Self.maxProfiles))
        self.activeID = self.profiles.contains { $0.id == activeID } ? activeID : nil
    }

    var active: TerminalColorProfile? { profiles.first { $0.id == activeID } }

    func profile(id: UUID) -> TerminalColorProfile? { profiles.first { $0.id == id } }

    /// Adds a profile and returns the id that now stands for it: the id of an identical scheme already listed
    /// (same colours and font), so importing one file twice does not fill the list. At the cap the oldest
    /// profile that is not active makes room.
    @discardableResult
    mutating func add(_ profile: TerminalColorProfile) -> UUID {
        if let same = profiles.first(where: { $0.sameScheme(as: profile) }) { return same.id }
        profiles.insert(profile, at: 0)
        while profiles.count > Self.maxProfiles {
            if let index = profiles.lastIndex(where: { $0.id != activeID }) { profiles.remove(at: index) } else { break }
        }
        return profile.id
    }

    /// nil selects the default theme. An unknown id is ignored.
    mutating func activate(_ id: UUID?) {
        guard let id else { activeID = nil; return }
        if profiles.contains(where: { $0.id == id }) { activeID = id }
    }

    mutating func rename(_ id: UUID, to name: String) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].name = TerminalColorProfile.sanitizedName(name, fallback: profiles[index].name)
    }

    mutating func remove(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        if activeID == id { activeID = nil }
    }
}

/// The stored form: versioned JSON. Anything unreadable, of another version, oversized or inconsistent decodes
/// to an empty library (the default theme), never to a crash or a half-trusted state.
enum TerminalProfileLibraryCodec {
    static let version = 1
    static let maxBytes = 256 * 1024

    private struct Envelope: Codable {
        var version: Int
        var activeID: UUID?
        var profiles: [TerminalColorProfile]
    }

    static func encode(_ library: TerminalProfileLibrary) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(Envelope(version: version, activeID: library.activeID, profiles: library.profiles))
    }

    static func decode(_ data: Data?) -> TerminalProfileLibrary {
        guard let data, data.count <= maxBytes else { return TerminalProfileLibrary() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(Envelope.self, from: data), envelope.version == version else {
            return TerminalProfileLibrary()
        }
        var seen = Set<UUID>()
        let valid = envelope.profiles.compactMap { profile -> TerminalColorProfile? in
            guard profile.ansi.count == TerminalRawColors.ansiCount, seen.insert(profile.id).inserted else { return nil }
            var clean = profile
            clean.name = TerminalColorProfile.sanitizedName(profile.name)
            clean.fontName = profile.fontName.map { TerminalColorProfile.sanitizedName($0, fallback: "") }.flatMap { $0.isEmpty ? nil : $0 }
            return clean
        }
        return TerminalProfileLibrary(profiles: valid, activeID: envelope.activeID)
    }
}
