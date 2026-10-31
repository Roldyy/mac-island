import ClaudeLiveKit
import Observation

/// Live Claude sessions for the tab. Polls only while the tab is on screen (start/stop from the view).
@MainActor @Observable
final class AgentsLiveModel {
    static let shared = AgentsLiveModel()

    @ObservationIgnored private let monitor: ClaudeLiveMonitor

    init(monitor: ClaudeLiveMonitor? = nil) {
        self.monitor = monitor ?? ClaudeLiveMonitor(
            source: ClaudeLiveSource(reader: ClaudeSessionReader(directory: ClaudeSessionReader.defaultDirectory)))
    }

    /// Working first, then waiting, then idle; same state by folder name for a stable list.
    var sessions: [ClaudeSession] { Self.sorted(monitor.sessions) }

    func start() { monitor.start() }
    func stop() { monitor.stop() }

    nonisolated static func label(for state: ClaudeSession.State) -> String {
        switch state {
        case .working: "travaille"
        case .waiting: "attend"
        case .idle: "inactif"
        case .unknown: "inconnu"
        }
    }

    nonisolated static func sorted(_ sessions: [ClaudeSession]) -> [ClaudeSession] {
        func rank(_ s: ClaudeSession.State) -> Int {
            switch s { case .working: 0; case .waiting: 1; case .idle: 2; case .unknown: 3 }
        }
        return sessions.sorted {
            rank($0.state) != rank($1.state) ? rank($0.state) < rank($1.state)
                : ($0.folderName, $0.pid) < ($1.folderName, $1.pid)
        }
    }
}
