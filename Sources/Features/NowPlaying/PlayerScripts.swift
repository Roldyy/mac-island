import Foundation

enum PlayerCommand: Sendable { case playPause, next, previous }

enum PlayerDurationUnit: Sendable { case seconds, milliseconds }

/// AppleScript source text. Every script is wrapped in `if application id "..." is running`, which
/// never launches the app, and targets it by bundle id. The Swift-side NSWorkspace check alone left a
/// window in which a player that was quitting got relaunched by the `tell`.
enum PlayerScripts {
    static let separator = "(ASCII character 31)"

    private static func guarded(_ bundleID: String, body: String, otherwise: String? = nil) -> String {
        var out = "if application id \"\(bundleID)\" is running then\n"
        out += body.split(separator: "\n", omittingEmptySubsequences: false).map { "    \($0)" }.joined(separator: "\n")
        if let otherwise { out += "\nelse\n    \(otherwise)" }
        return out + "\nend if"
    }

    static func status(bundleID: String) -> String {
        let artwork = bundleID == BundleIDs.spotify ? "artwork url of current track" : "\"\""
        let duration = "duration of current track"
        let body = """
        tell application id "\(bundleID)"
            set st to player state as text
            if st is "stopped" then return "stopped"
            set d to \(separator)
            return st & d & (name of current track) & d & (artist of current track) & d & (album of current track) & d & ((player position) as text) & d & ((\(duration)) as text) & d & (\(artwork))
        end tell
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

/// Pure parser of the status script output.
enum PlayerScriptParser {
    static func parse(_ raw: String, bundleID: String,
                             durationUnit: PlayerDurationUnit) throws -> NowPlayingSnapshot? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text == "stopped" || text == "none" { return nil }
        let f = text.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
        guard f.count == 7, let position = number(f[4]), let duration = number(f[5]) else {
            throw NowPlayingError.malformedOutput
        }
        let url = f[6] == "missing value" ? nil : URL(string: f[6].trimmingCharacters(in: .whitespaces))
        return NowPlayingSnapshot(
            title: f[1], artist: f[2], album: f[3],
            artworkURL: url.flatMap { $0.scheme?.hasPrefix("http") == true ? $0 : nil },
            artworkData: nil, isPlaying: f[0] == "playing", position: position,
            duration: durationUnit == .milliseconds ? duration / 1000 : duration,
            sourceBundleID: bundleID)
    }

    /// AppleScript formats reals with the user's decimal separator.
    private static func number(_ s: String) -> Double? {
        Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
}
