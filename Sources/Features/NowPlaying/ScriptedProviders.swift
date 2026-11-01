import Foundation

/// Provider for an AppleScript-capable player. Queries only when the app is running.
/// Every failure is thrown, never turned into "nothing playing": the model reports its cause.
actor SpotifyProvider: NowPlayingProvider {
    nonisolated let bundleID = BundleIDs.spotify
    private let runner: AppleScriptRunning
    private let running: RunningAppChecking

    init(runner: AppleScriptRunning, running: RunningAppChecking = WorkspaceRunningChecker()) {
        self.runner = runner; self.running = running
    }

    func snapshot() async throws -> NowPlayingSnapshot? {
        guard running.isRunning(bundleID: bundleID) else { return nil }
        let out = try await runner.run(PlayerScripts.status(bundleID: bundleID))
        return try PlayerScriptParser.parse(out.text ?? "", bundleID: bundleID, durationUnit: .milliseconds)
    }
}

/// Apple Music. Artwork is raw data: fetched once per track, cached by track key.
actor MusicProvider: NowPlayingProvider {
    nonisolated let bundleID = BundleIDs.music
    private let runner: AppleScriptRunning
    private let running: RunningAppChecking
    private var artworkKey: String?
    private var artwork: Data?

    init(runner: AppleScriptRunning, running: RunningAppChecking = WorkspaceRunningChecker()) {
        self.runner = runner; self.running = running
    }

    func snapshot() async throws -> NowPlayingSnapshot? {
        guard running.isRunning(bundleID: bundleID) else { return nil }
        let out = try await runner.run(PlayerScripts.status(bundleID: bundleID))
        guard var snap = try PlayerScriptParser.parse(out.text ?? "", bundleID: bundleID, durationUnit: .seconds)
        else { return nil }
        if artworkKey != snap.trackKey {
            artworkKey = snap.trackKey
            // A track without artwork raises an error: that is an empty cover, not a failure.
            artwork = try? await runner.run(PlayerScripts.artworkData(bundleID: bundleID)).data
        }
        snap.artworkData = artwork
        return snap
    }
}
