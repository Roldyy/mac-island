import Foundation
import OSLog

/// Why a player that is open could not be read, in one short French line for the Home card and one
/// log line. The line holds the player name and an error number, never a title or an artist.
struct NowPlayingFault: Equatable, Sendable {
    enum Kind: String, Sendable {
        case denied, consentRequired, timeout, notFound, noTrack, emptyReply, unreadable, other
        /// macOS could not say where the Automation permission stands (the silent check, not a script).
        case automation
    }

    var player: String
    var kind: Kind
    var code: Int?

    init(player: String, kind: Kind, code: Int? = nil) {
        self.player = player
        self.kind = kind
        self.code = code
    }

    init(_ error: NowPlayingError, bundleID: String) {
        let player = PlayerNames.name(for: bundleID)
        switch error {
        case .permissionDenied: self.init(player: player, kind: .denied, code: -1743)
        case .consentRequired: self.init(player: player, kind: .consentRequired, code: -1744)
        case .timedOut: self.init(player: player, kind: .timeout, code: -1712)
        case .appNotFound: self.init(player: player, kind: .notFound, code: -600)
        case .noCurrentTrack: self.init(player: player, kind: .noTrack, code: -1728)
        case .emptyReply: self.init(player: player, kind: .emptyReply)
        case .malformedOutput: self.init(player: player, kind: .unreadable)
        case .scriptFailed(let code): self.init(player: player, kind: .other, code: code)
        }
    }

    /// "Spotify : autorisation refusée (-1743)".
    var line: String {
        let number = code.map { " (\($0))" } ?? ""
        let what: String = switch kind {
        case .denied: "autorisation refusée"
        case .consentRequired: "autorisation à accorder"
        case .timeout: "pas de réponse"
        case .notFound: "application introuvable"
        case .noTrack: "aucun morceau lisible"
        case .emptyReply: "réponse vide"
        case .unreadable: "réponse illisible"
        case .other: "erreur AppleScript"
        case .automation: "autorisation indéterminée"
        }
        return "\(player) : \(what)\(number)"
    }
}

/// One line per failed reading in the unified log (`log show --predicate 'subsystem == "be.roldy.macisland"'`).
/// Only the player, the kind and the error number are public: never a title, an artist or an album.
enum NowPlayingLog {
    private static let log = Logger(subsystem: "be.roldy.macisland", category: "nowplaying")

    static func record(_ fault: NowPlayingFault) {
        log.notice("reading failed: player=\(fault.player, privacy: .public) kind=\(fault.kind.rawValue, privacy: .public) code=\(fault.code ?? 0, privacy: .public)")
    }

}
