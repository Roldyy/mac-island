import ClaudeLiveKit
import Foundation

struct FinishedSession: Equatable, Sendable {
    var folderName: String
    var at: Date
}

/// Notices a session that stopped working (went idle or waiting, or disappeared) between two looks.
/// Pure state machine: feed it each snapshot of the sessions.
struct FinishTracker: Equatable, Sendable {
    private var wasWorking: [String: String] = [:]   // session id -> folder name
    private(set) var last: FinishedSession?

    mutating func update(_ sessions: [ClaudeSession], now: Date) {
        var working: [String: String] = [:]
        for session in sessions where session.state == .working { working[session.id] = session.folderName }
        for (id, folder) in wasWorking where working[id] == nil {
            last = FinishedSession(folderName: folder, at: now)
        }
        wasWorking = working
    }
}
