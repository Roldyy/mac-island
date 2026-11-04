import AppKit
import Foundation

/// One reading handed over by the system Now Playing adapter (the event driven perl MediaRemote reader that PortKit
/// runs). Plain public value: this module imports no PortKit, the app maps one to the other.
///
/// While the adapter delivers, it is the single source of truth: the model does not poll AppleScript at all.
public struct NowPlayingAdapterReading: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var artworkData: Data?
    public var isPlaying: Bool
    /// Seconds at `sampledAt`.
    public var position: TimeInterval
    public var duration: TimeInterval
    /// Playback rate (1 = normal): the position moves by `rate` seconds per second while playing.
    public var rate: Double
    public var sampledAt: Date
    public var bundleID: String

    public init(title: String, artist: String, album: String, artworkData: Data?, isPlaying: Bool,
                position: TimeInterval, duration: TimeInterval, rate: Double, sampledAt: Date, bundleID: String) {
        self.title = title; self.artist = artist; self.album = album; self.artworkData = artworkData
        self.isPlaying = isPlaying; self.position = position; self.duration = duration
        self.rate = rate; self.sampledAt = sampledAt; self.bundleID = bundleID
    }

    /// The position at `date`: the sampled one plus the time played since, never past the duration.
    func position(at date: Date) -> TimeInterval {
        guard isPlaying else { return position }
        let moved = position + max(0, date.timeIntervalSince(sampledAt)) * max(0, rate)
        return duration > 0 ? min(duration, moved) : moved
    }

    func snapshot(at date: Date) -> NowPlayingSnapshot {
        NowPlayingSnapshot(title: title, artist: artist, album: album, artworkURL: nil, artworkData: artworkData,
                           isPlaying: isPlaying, position: position(at: date), duration: duration,
                           sourceBundleID: bundleID)
    }
}

/// Launch and quit of the player apps, as events. The model never polls NSWorkspace for "is a player running":
/// it listens to these and re-arms (or ends) its poll when one fires.
@MainActor
protocol AppLifecycleWatching: AnyObject {
    func start(bundleIDs: [String], onChange: @escaping @MainActor () -> Void)
    func stop()
}

/// NSWorkspace launch / terminate notifications, filtered to the given bundle ids.
@MainActor
final class WorkspaceAppEvents: AppLifecycleWatching {
    private var tokens: [NSObjectProtocol] = []

    init() {}

    func start(bundleIDs: [String], onChange: @escaping @MainActor () -> Void) {
        guard tokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let id = app?.bundleIdentifier, bundleIDs.contains(id) else { return }
                MainActor.assumeIsolated { onChange() }
            })
        }
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for token in tokens { center.removeObserver(token) }
        tokens = []
    }
}
