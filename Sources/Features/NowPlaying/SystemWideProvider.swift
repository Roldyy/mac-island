import Foundation

/// SLOT, NO IMPLEMENTATION. A future provider covering browsers and every other app.
///
/// Why it is empty: since macOS 15.4 the private MediaRemote framework only answers entitled
/// processes, so reading the system-wide Now Playing item needs something that runs inside an
/// entitled process (for example a helper that loads MediaRemote through a platform binary such
/// as `perl`, the approach of the open-source "mediaremote-adapter"). That is a third-party
/// component to review, pin and ship, so it is not part of this lane.
///
/// A conforming type returns the system-wide snapshot with `sourceBundleID` set to the real
/// owner (browser, podcast app...). `NowPlayingAggregator` already handles it like any provider,
/// and `NowPlayingTransport` already falls back to media keys for non-scripted sources.
protocol SystemWideProvider: NowPlayingProvider {
    /// Start the helper process or XPC connection. Idempotent.
    func start() async throws
    /// Stop it; called when the tab is hidden.
    func stop() async
}
