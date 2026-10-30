import Foundation
import Observation

@MainActor @Observable
public final class NowPlayingModel {
    public enum Access: Equatable { case needsAuthorization, ready, denied }

    public private(set) var snapshot: NowPlayingSnapshot?
    public private(set) var artwork: Data?
    public private(set) var access: Access

    private static let flagKey = "nowplaying.automationRequested"
    private let providers: [any NowPlayingProvider]
    private var aggregator: NowPlayingAggregator
    private let defaults: UserDefaults
    private let interval: Duration
    private let transport: NowPlayingTransport?
    private let artworkLoader: ArtworkLoader?
    private var visible = false
    private var task: Task<Void, Never>?
    private var artworkKey: String?

    public init(providers: [any NowPlayingProvider], defaults: UserDefaults = .standard,
                interval: Duration = .seconds(1), transport: NowPlayingTransport?, artwork: ArtworkLoader?) {
        self.providers = providers
        self.defaults = defaults
        self.interval = interval
        self.transport = transport
        self.artworkLoader = artwork
        self.aggregator = NowPlayingAggregator()
        self.access = defaults.bool(forKey: Self.flagKey) ? .ready : .needsAuthorization
    }

    /// Live wiring: Spotify + Music over AppleScript, media keys as transport fallback.
    public static func live() -> NowPlayingModel {
        let runner = AppleScriptRunner()
        return NowPlayingModel(
            providers: [SpotifyProvider(runner: runner), MusicProvider(runner: runner)],
            transport: NowPlayingTransport(runner: runner), artwork: ArtworkLoader())
    }

    /// The view calls this on appear/disappear. Polling exists only while visible AND the
    /// user pressed "Autoriser" once (the Automation prompt must never fire by itself).
    public func setVisible(_ v: Bool) {
        visible = v
        updatePolling()
    }

    /// The "Autoriser" button: the first query is what makes macOS ask for Automation.
    public func authorize() async {
        defaults.set(true, forKey: Self.flagKey)
        access = .ready
        await poll()
        updatePolling()
    }

    public func send(_ command: PlayerCommand) {
        let source = snapshot?.sourceBundleID
        guard let transport else { return }
        Task { [weak self] in
            await transport.send(command, source: source)
            try? await Task.sleep(for: .milliseconds(250))
            await self?.poll()
        }
    }

    func poll() async {
        let gathered = await NowPlayingAggregator.gather(from: providers)
        let out = aggregator.resolve(gathered)
        if out.permissionDenied { access = .denied; snapshot = nil; artwork = nil; return }
        access = .ready
        snapshot = out.snapshot
        await refreshArtwork()
    }

    private func refreshArtwork() async {
        guard let s = snapshot, let loader = artworkLoader else { artwork = nil; artworkKey = nil; return }
        if artworkKey == s.trackKey { return }
        artworkKey = s.trackKey
        artwork = await loader.artwork(for: s)
    }

    private func updatePolling() {
        task?.cancel()
        task = nil
        guard visible, access != .needsAuthorization else { return }
        task = Task { [weak self, interval] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: interval)
            }
        }
    }
}
