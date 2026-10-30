import Foundation

public enum PlayerCommand: Sendable { case playPause, next, previous }

public enum PlayerDurationUnit: Sendable { case seconds, milliseconds }

/// AppleScript source text. Every script targets the app by bundle id, and callers only run
/// them after an NSWorkspace check, so a query never launches the app.
public enum PlayerScripts {
    static let separator = "(ASCII character 31)"

    static func status(bundleID: String) -> String {
        let artwork = bundleID == BundleIDs.spotify ? "artwork url of current track" : "\"\""
        let duration = "duration of current track"
        return """
        tell application id "\(bundleID)"
            set st to player state as text
            if st is "stopped" then return "stopped"
            set d to \(separator)
            return st & d & (name of current track) & d & (artist of current track) & d & (album of current track) & d & ((player position) as text) & d & ((\(duration)) as text) & d & (\(artwork))
        end tell
        """
    }

    static func artworkData(bundleID: String) -> String {
        "tell application id \"\(bundleID)\" to return data of artwork 1 of current track"
    }

    static func command(_ c: PlayerCommand, bundleID: String) -> String {
        let verb = switch c {
        case .playPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        }
        return "tell application id \"\(bundleID)\" to \(verb)"
    }
}

/// Pure parser of the status script output.
public enum PlayerScriptParser {
    public static func parse(_ raw: String, bundleID: String,
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
