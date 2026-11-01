import Foundation

enum NowPlayingError: Error, Equatable, Sendable {
    /// Automation permission refused (AppleScript error -1743).
    case permissionDenied
    /// Automation permission never asked (-1744): the system would have to prompt.
    case consentRequired
    /// The player did not answer in time (-1712).
    case timedOut
    /// AppleScript could not find the player (-600).
    case appNotFound
    /// The player has no current track (-1728). Not a normal "nothing playing": the status script
    /// already returns "stopped" for that, so this one is reported, never swallowed.
    case noCurrentTrack
    /// The script ran and returned nothing readable (not a string, or an empty one).
    case emptyReply
    case scriptFailed(code: Int)
    case malformedOutput

    static func from(scriptErrorCode code: Int) -> NowPlayingError {
        switch code {
        case -1743: .permissionDenied
        case -1744: .consentRequired
        case -1712: .timedOut
        case -600: .appNotFound
        case -1728: .noCurrentTrack
        default: .scriptFailed(code: code)
        }
    }

    /// The AppleScript error number behind the case, when there is one.
    var code: Int? {
        switch self {
        case .permissionDenied: -1743
        case .consentRequired: -1744
        case .timedOut: -1712
        case .appNotFound: -600
        case .noCurrentTrack: -1728
        case .scriptFailed(let code): code
        case .emptyReply, .malformedOutput: nil
        }
    }
}

/// A source of now-playing information. `snapshot()` returns nil when the source has nothing
/// to report (app not running, stopped). It must never launch the app it observes.
protocol NowPlayingProvider: Sendable {
    var bundleID: String { get }
    func snapshot() async throws -> NowPlayingSnapshot?
}
