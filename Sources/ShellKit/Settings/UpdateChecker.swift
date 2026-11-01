import Foundation
import Observation

/// A release version as GitHub tags it (`v2.0.0`, `2.0.0-beta.1`): numbers first, then an optional pre-release label.
/// A pre-release sorts before its own release, as in semantic versioning.
public struct ReleaseVersion: Comparable, Equatable, Sendable {
    public let numbers: [Int]
    public let preRelease: [String]

    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        // Build metadata never takes part in the comparison.
        if let plus = text.firstIndex(of: "+") { text = String(text[..<plus]) }
        let parts = text.split(separator: "-", maxSplits: 1).map(String.init)
        guard let head = parts.first, !head.isEmpty else { return nil }
        let numbers = head.split(separator: ".").map { Int($0) }
        guard !numbers.isEmpty, !numbers.contains(nil) else { return nil }
        self.numbers = numbers.compactMap { $0 }
        preRelease = parts.count > 1 ? parts[1].split(separator: ".").map(String.init) : []
    }

    public var isPreRelease: Bool { !preRelease.isEmpty }

    public static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        let count = max(lhs.numbers.count, rhs.numbers.count)
        for index in 0..<count {
            let a = index < lhs.numbers.count ? lhs.numbers[index] : 0
            let b = index < rhs.numbers.count ? rhs.numbers[index] : 0
            if a != b { return a < b }
        }
        if lhs.preRelease.isEmpty != rhs.preRelease.isEmpty { return !lhs.preRelease.isEmpty }
        for (a, b) in zip(lhs.preRelease, rhs.preRelease) where a != b {
            if let x = Int(a), let y = Int(b) { return x < y }
            return a < b
        }
        return lhs.preRelease.count < rhs.preRelease.count
    }
}

/// One published release, as far as the page needs it.
public struct PublishedRelease: Equatable, Sendable {
    public let version: ReleaseVersion
    public let tag: String
    public let pageURL: URL
    public let isPreRelease: Bool
    /// The release notes the author wrote on GitHub (Markdown, as is).
    public var notes: String = ""
}

/// "Mises à jour" of the About page: asks GitHub which release is newest, and says so. Nothing is downloaded or installed
/// from here: an app cannot replace itself while it runs, so the release page opens and the person drags the new app in.
///
/// Network: one GET to `api.github.com/repos/Roldyy/mac-island/releases`, only when the person presses "Rechercher
/// maintenant", or, with "Rechercher les mises à jour automatiquement" on, when Settings opens and the last check is
/// older than a day. No identifier is sent.
@MainActor @Observable
public final class UpdateChecker {
    public enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(PublishedRelease)
        case failed(String)
    }

    public static let releasesURL = URL(string: "https://api.github.com/repos/Roldyy/mac-island/releases?per_page=15")!
    public static let lastCheckKey = "macisland.updates.lastCheck"
    public static let autoKey = "autoCheckUpdates"
    public static let betaKey = "includeBetaUpdates"
    static let staleAfter: TimeInterval = 24 * 3600

    public static let shared = UpdateChecker()

    public private(set) var state: State = .idle
    public private(set) var lastCheck: Date?

    @ObservationIgnored private let fetch: @Sendable (URL) async throws -> Data
    @ObservationIgnored private let currentVersion: () -> String
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var running = false

    public init(fetch: @escaping @Sendable (URL) async throws -> Data = UpdateChecker.liveFetch,
                currentVersion: @escaping () -> String = { AboutVersion.current() },
                now: @escaping () -> Date = Date.init) {
        self.fetch = fetch
        self.currentVersion = currentVersion
        self.now = now
    }

    public static let liveFetch: @Sendable (URL) async throws -> Data = { url in
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MacIsland-UpdateCheck", forHTTPHeaderField: "User-Agent")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// Reads the stored time of the last check (once the page or the window needs it).
    public func loadLastCheck(from defaults: UserDefaults) {
        if let stamp = defaults.object(forKey: Self.lastCheckKey) as? Double { lastCheck = Date(timeIntervalSince1970: stamp) }
    }

    /// The automatic check: only when the switch is on and the last check is a day old.
    public func checkIfStale(defaults: UserDefaults) async {
        loadLastCheck(from: defaults)
        guard defaults.object(forKey: Self.autoKey) as? Bool ?? true else { return }
        if let lastCheck, now().timeIntervalSince(lastCheck) < Self.staleAfter { return }
        await check(defaults: defaults)
    }

    public func check(defaults: UserDefaults) async {
        guard !running else { return }
        running = true
        state = .checking
        defer { running = false }
        let includeBeta = defaults.object(forKey: Self.betaKey) as? Bool ?? false
        do {
            let data = try await fetch(Self.releasesURL)
            let releases = try Self.parse(data)
            let stamp = now()
            lastCheck = stamp
            defaults.set(stamp.timeIntervalSince1970, forKey: Self.lastCheckKey)
            state = Self.verdict(releases: releases, current: currentVersion(), includeBeta: includeBeta)
        } catch {
            state = .failed("Impossible de joindre GitHub : \(error.localizedDescription)")
        }
    }

    /// Pure: what the page says about a list of releases.
    static func verdict(releases: [PublishedRelease], current: String, includeBeta: Bool) -> State {
        guard let installed = ReleaseVersion(current) else {
            // A development build has no version to compare: say so rather than call it up to date.
            return .failed("Cette version (« \(current) ») n’a pas de numéro à comparer.")
        }
        let candidates = releases.filter { includeBeta || !$0.isPreRelease }
        guard let newest = candidates.max(by: { $0.version < $1.version }) else { return .upToDate }
        return newest.version > installed ? .available(newest) : .upToDate
    }

    /// Pure: the releases of the GitHub API answer, drafts left out.
    static func parse(_ data: Data) throws -> [PublishedRelease] {
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }
        return array.compactMap { entry in
            guard entry["draft"] as? Bool != true, let tag = entry["tag_name"] as? String,
                  let version = ReleaseVersion(tag),
                  let html = entry["html_url"] as? String, let url = URL(string: html),
                  url.scheme == "https", url.host == "github.com" else { return nil }
            return PublishedRelease(version: version, tag: tag, pageURL: url,
                                    isPreRelease: entry["prerelease"] as? Bool == true || version.isPreRelease,
                                    notes: entry["body"] as? String ?? "")
        }
    }
}

/// The running app's version, read from its bundle.
public enum AboutVersion {
    public static func current(bundle: Bundle = .main) -> String {
        (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "développement"
    }
}

/// "Afficher les nouveautés après mise à jour" (`releaseNotesOnUpdate`): the first time Settings opens on a version
/// other than the one last seen (`whatsNewSeenVersion`, the migrated key), "Nouveautés" opens once. A first run has no
/// version on record: it only records the current one.
public enum WhatsNewAfterUpdate {
    public static let seenKey = "whatsNewSeenVersion"
    public static let wantedKey = "releaseNotesOnUpdate"

    /// True when the page should open now; records the version either way.
    public static func consume(defaults: UserDefaults, current: String) -> Bool {
        let seen = defaults.string(forKey: seenKey)
        guard seen != current else { return false }
        defaults.set(current, forKey: seenKey)
        guard let seen, !seen.isEmpty else { return false }
        return defaults.object(forKey: wantedKey) as? Bool ?? true
    }
}
