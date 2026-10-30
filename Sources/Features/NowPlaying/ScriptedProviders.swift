import Foundation

/// Provider for an AppleScript-capable player. Queries only when the app is running.
public actor SpotifyProvider: NowPlayingProvider {
    public nonisolated let bundleID = BundleIDs.spotify
    private let runner: AppleScriptRunning
    private let running: RunningAppChecking

    public init(runner: AppleScriptRunning, running: RunningAppChecking = WorkspaceRunningChecker()) {
        self.runner = runner; self.running = running
    }

    public func snapshot() async throws -> NowPlayingSnapshot? {
        guard running.isRunning(bundleID: bundleID) else { return nil }
        do {
            let out = try await runner.run(PlayerScripts.status(bundleID: bundleID))
            return try PlayerScriptParser.parse(out.text ?? "", bundleID: bundleID, durationUnit: .milliseconds)
        } catch NowPlayingError.noCurrentTrack {
            return nil
        }
    }
}

/// Apple Music. Artwork is raw data: fetched once per track, cached by track key.
public actor MusicProvider: NowPlayingProvider {
    public nonisolated let bundleID = BundleIDs.music
    private let runner: AppleScriptRunning
    private let running: RunningAppChecking
    private var artworkKey: String?
    private var artwork: Data?

    public init(runner: AppleScriptRunning, running: RunningAppChecking = WorkspaceRunningChecker()) {
        self.runner = runner; self.running = running
    }

    public func snapshot() async throws -> NowPlayingSnapshot? {
        guard running.isRunning(bundleID: bundleID) else { return nil }
        var snap: NowPlayingSnapshot
        do {
            let out = try await runner.run(PlayerScripts.status(bundleID: bundleID))
            guard let s = try PlayerScriptParser.parse(out.text ?? "", bundleID: bundleID, durationUnit: .seconds)
            else { return nil }
            snap = s
        } catch NowPlayingError.noCurrentTrack {
            return nil
        }
        if artworkKey != snap.trackKey {
            artworkKey = snap.trackKey
            // A track without artwork raises an error: that is an empty cover, not a failure.
            artwork = try? await runner.run(PlayerScripts.artworkData(bundleID: bundleID)).data
        }
        snap.artworkData = artwork
        return snap
    }
}
