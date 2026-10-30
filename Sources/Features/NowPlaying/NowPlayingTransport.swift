import Foundation

/// play/pause, next, previous. Direct AppleScript when the active source is a running
/// Spotify or Music, system media keys for every other app (and as fallback if the script fails).
struct NowPlayingTransport: Sendable {
    private let runner: AppleScriptRunning
    private let running: RunningAppChecking
    private let postKey: @Sendable (MediaKey) -> Void

    init(runner: AppleScriptRunning, running: RunningAppChecking = WorkspaceRunningChecker(),
                postKey: @escaping @Sendable (MediaKey) -> Void = { MediaKeyEvent.post($0) }) {
        self.runner = runner; self.running = running; self.postKey = postKey
    }

    func send(_ command: PlayerCommand, source: String?) async {
        if let source, [BundleIDs.spotify, BundleIDs.music].contains(source), running.isRunning(bundleID: source) {
            do {
                _ = try await runner.run(PlayerScripts.command(command, bundleID: source))
                return
            } catch {
                // fall through to the media key
            }
        }
        let key: MediaKey = switch command {
        case .playPause: .playPause
        case .next: .next
        case .previous: .previous
        }
        postKey(key)
    }
}
