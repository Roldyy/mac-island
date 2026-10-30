import Foundation

enum NowPlayingError: Error, Equatable, Sendable {
    /// Automation permission refused (AppleScript error -1743).
    case permissionDenied
    /// Player is open but has no current track (AppleScript error -1728).
    case noCurrentTrack
    case scriptFailed(code: Int)
    case malformedOutput

    static func from(scriptErrorCode code: Int) -> NowPlayingError {
        switch code {
        case -1743: .permissionDenied
        case -1728: .noCurrentTrack
        default: .scriptFailed(code: code)
        }
    }
}

/// A source of now-playing information. `snapshot()` returns nil when the source has nothing
/// to report (app not running, stopped). It must never launch the app it observes.
protocol NowPlayingProvider: Sendable {
    var bundleID: String { get }
    func snapshot() async throws -> NowPlayingSnapshot?
}
