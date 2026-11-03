import Foundation

/// The settings that decide which music app a click opens: the preferred-player page and the Music-app blocker page.
public struct MusicPlayerSettings: Equatable, Sendable {
    /// `NotchPreferredPlayer` choice ("" = left to the island).
    public static let preferredKey = "notchPreferredPlayer"
    /// "Bloqueur Music" switch.
    public static let blockerKey = "musicBlockEnabled"
    /// App bundle path the blocker opens instead of Music ("" = none).
    public static let replacementPathKey = "musicBlockReplacementPath"

    public var preferred: String
    public var blockerOn: Bool
    /// Bundle id of the blocker's replacement app, when one is set.
    public var replacementBundleID: String?

    public init(preferred: String = "", blockerOn: Bool = false, replacementBundleID: String? = nil) {
        self.preferred = preferred
        self.blockerOn = blockerOn
        self.replacementBundleID = replacementBundleID
    }

    /// Reads the three keys the settings pages write. `bundleID` maps the replacement path to its bundle id.
    public static func read(from defaults: UserDefaults,
                            bundleID: (String) -> String? = { Bundle(url: URL(fileURLWithPath: $0))?.bundleIdentifier }) -> MusicPlayerSettings {
        let preferred = defaults.string(forKey: preferredKey) ?? ""
        let path = defaults.string(forKey: replacementPathKey) ?? ""
        return MusicPlayerSettings(preferred: preferred.utf8.count <= 256 ? preferred : "",
                                   blockerOn: defaults.bool(forKey: blockerKey),
                                   replacementBundleID: path.isEmpty ? nil : bundleID(path))
    }
}

/// The one rule for "which music app does this click open". Pure: nothing here touches NSWorkspace.
public enum MusicPlayerResolver {
    public static let spotifyBundleID = "com.spotify.client"
    public static let musicBundleIDs: Set<String> = ["com.apple.Music", "com.apple.iTunes"]
    public static let spotifyInstallURL = URL(string: "https://www.spotify.com/download")!

    public enum Outcome: Equatable, Sendable {
        case open(bundleID: String)
        /// The chosen player is missing: its install page.
        case installPage(URL)
    }

    /// Order: the app playing now, the chosen player, the app that played last, the blocker's replacement, Spotify.
    /// Apple Music is dropped from every step while the blocker is on or Spotify is the chosen player, so a stale
    /// "last track from Music" can no longer open it. Nothing usable: Spotify's install page.
    public static func resolve(playing: String?, last: String?, settings: MusicPlayerSettings,
                               isInstalled: (String) -> Bool) -> Outcome {
        let forbidsMusic = settings.blockerOn || settings.preferred == spotifyBundleID
        let candidates: [String?] = [playing, settings.preferred.isEmpty ? nil : settings.preferred, last,
                                     settings.blockerOn ? settings.replacementBundleID : nil, spotifyBundleID]
        for case let id? in candidates where !id.isEmpty && !(forbidsMusic && musicBundleIDs.contains(id)) {
            if isInstalled(id) { return .open(bundleID: id) }
        }
        return .installPage(spotifyInstallURL)
    }
}
