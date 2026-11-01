import Foundation

enum PlayerCommand: Sendable { case playPause, next, previous }

enum PlayerDurationUnit: Sendable { case seconds, milliseconds }

/// AppleScript source text. Every script is wrapped in `if application id "..." is running`, which
/// never launches the app, and targets it by bundle id. The Swift-side NSWorkspace check alone left a
/// window in which a player that was quitting got relaunched by the `tell`.
enum PlayerScripts {
    static let separator = "(ASCII character 31)"
    /// A player that hangs must not hold the script queue for the two minutes AppleScript waits by default:
    /// past this the script fails with -1712, which the card shows.
    static let timeoutSeconds = 4

    private static func guarded(_ bundleID: String, body: String, otherwise: String? = nil) -> String {
        var out = "if application id \"\(bundleID)\" is running then\n"
        out += body.split(separator: "\n", omittingEmptySubsequences: false).map { "    \($0)" }.joined(separator: "\n")
        if let otherwise { out += "\nelse\n    \(otherwise)" }
        return out + "\nend if"
    }

    /// The first Apple Event (`player state`) is outside any `try`, so a refused or missing permission and a
    /// timeout reach the caller as their own error number. Every track field after it is read on its own inside
    /// a `try`: a track with no album, a podcast or an advertisement still gives a reading, and one missing
    /// property never turns a playing track into "nothing loaded".
    static func status(bundleID: String) -> String {
        let artwork = bundleID == BundleIDs.spotify ? "artwork url of current track" : "\"\""
        let body = """
        with timeout of \(timeoutSeconds) seconds
            tell application id "\(bundleID)"
                set st to player state as text
                if st is "stopped" or st contains "kPSS" then return "stopped"
                set d to \(separator)
                set vTitle to ""
                set vArtist to ""
                set vAlbum to ""
                set vPos to "0"
                set vDur to "0"
                set vArt to ""
                try
                    set vTitle to (name of current track) as text
                end try
                try
                    set vArtist to (artist of current track) as text
                end try
                try
                    set vAlbum to (album of current track) as text
                end try
                try
                    set vPos to (player position) as text
                end try
                try
                    set vDur to (duration of current track) as text
                end try
                try
                    set vArt to (\(artwork)) as text
                end try
                return st & d & vTitle & d & vArtist & d & vAlbum & d & vPos & d & vDur & d & vArt
            end tell
        end timeout
        """
        return guarded(bundleID, body: body, otherwise: "return \"none\"")
    }

    /// Not running: error -1728, which the caller turns into "no cover".
    static func artworkData(bundleID: String) -> String {
        guarded(bundleID, body: "tell application id \"\(bundleID)\" to return data of artwork 1 of current track",
                otherwise: "error number -1728")
    }

    static func command(_ c: PlayerCommand, bundleID: String) -> String {
        let verb = switch c {
        case .playPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        }
        return guarded(bundleID, body: "tell application id \"\(bundleID)\" to \(verb)")
    }
}

/// The player state as the status script returns it, tolerant of how AppleScript prints an enumeration:
/// the word, or the raw four-letter code when the dictionary was not applied (`kPSP` playing, `kPSp` paused,
/// `kPSS` stopped).
enum PlayerStateText: Equatable, Sendable {
    case playing, paused, stopped

    init?(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.contains("kPSP") { self = .playing; return }
        if text.contains("kPSp") { self = .paused; return }
        if text.contains("kPSS") { self = .stopped; return }
        switch text.lowercased() {
        case "playing", "fast forwarding", "rewinding": self = .playing
        case "paused": self = .paused
        case "stopped": self = .stopped
        default: return nil
        }
    }
}

/// Pure parser of the status script output.
enum PlayerScriptParser {
    /// nil: the player is closed or stopped (a real "nothing playing"). An empty reply and a reply it cannot
    /// read throw, so the card can say why instead of passing them off as "nothing loaded".
    static func parse(_ raw: String, bundleID: String,
                             durationUnit: PlayerDurationUnit) throws -> NowPlayingSnapshot? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { throw NowPlayingError.emptyReply }
        if text == "stopped" || text == "none" { return nil }
        let f = text.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
        guard f.count == 7, let state = PlayerStateText(f[0]) else { throw NowPlayingError.malformedOutput }
        if state == .stopped { return nil }
        let duration = number(f[5])
        let url = f[6] == "missing value" ? nil : URL(string: f[6].trimmingCharacters(in: .whitespaces))
        return NowPlayingSnapshot(
            title: field(f[1]), artist: field(f[2]), album: field(f[3]),
            artworkURL: url.flatMap { $0.scheme?.hasPrefix("http") == true ? $0 : nil },
            artworkData: nil, isPlaying: state == .playing, position: number(f[4]),
            duration: durationUnit == .milliseconds ? duration / 1000 : duration,
            sourceBundleID: bundleID)
    }

    /// AppleScript prints `missing value` for a property the player does not have.
    private static func field(_ s: String) -> String { s == "missing value" ? "" : s }

    /// AppleScript formats reals with the user's decimal separator. An unreadable number is 0 (position at
    /// the start, duration unknown): losing the progress bar must never lose the track.
    private static func number(_ s: String) -> Double {
        let cleaned = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite, value >= 0 else { return 0 }
        return value
    }
}
