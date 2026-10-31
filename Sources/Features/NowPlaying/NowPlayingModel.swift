import Foundation
import Observation

/// The one flag the model persists. UserDefaults in the app, an in-memory fake in tests, so a
/// test never writes a plist into ~/Library/Preferences.
protocol NowPlayingFlagStore {
    func bool(forKey key: String) -> Bool
    func set(_ value: Bool, forKey key: String)
}

extension UserDefaults: NowPlayingFlagStore {}

@MainActor @Observable
final class NowPlayingModel {
    enum Access: Equatable { case needsAuthorization, ready, denied }

    private(set) var snapshot: NowPlayingSnapshot?
    private(set) var artwork: Data?
    private(set) var access: Access

    private static let flagKey = "nowplaying.automationRequested"
    private let providers: [any NowPlayingProvider]
    private var aggregator: NowPlayingAggregator
    private let defaults: any NowPlayingFlagStore
    private let artworkTimeout: Duration
    private let interval: Duration
    private let transport: NowPlayingTransport?
    private let artworkLoader: (any ArtworkLoading)?
    private var visible = false
    private var background = false
    /// Called after every poll with what is playing (nil when nothing or access missing). The closed island listens.
    var onSnapshot: ((NowPlayingSnapshot?) -> Void)?
    private var task: Task<Void, Never>?
    private var artworkKey: String?
    private var artworkTask: Task<Void, Never>?

    init(providers: [any NowPlayingProvider], defaults: any NowPlayingFlagStore = UserDefaults.standard,
                interval: Duration = .seconds(1), transport: NowPlayingTransport?, artwork: (any ArtworkLoading)?,
         artworkTimeout: Duration = .seconds(5)) {
        self.artworkTimeout = artworkTimeout
        self.providers = providers
        self.defaults = defaults
        self.interval = interval
        self.transport = transport
        self.artworkLoader = artwork
        self.aggregator = NowPlayingAggregator()
        self.access = defaults.bool(forKey: Self.flagKey) ? .ready : .needsAuthorization
    }

    /// Live wiring: Spotify + Music over AppleScript, media keys as transport fallback.
    static func live() -> NowPlayingModel {
        let runner = AppleScriptRunner()
        return NowPlayingModel(
            providers: [SpotifyProvider(runner: runner), MusicProvider(runner: runner)],
            transport: NowPlayingTransport(runner: runner), artwork: ArtworkLoader())
    }

    /// The view calls this on appear/disappear. Polling exists only while visible AND the
    /// user pressed "Autoriser" once (the Automation prompt must never fire by itself).
    func setVisible(_ v: Bool) {
        visible = v
        updatePolling()
    }

    /// The "Autoriser" button: the first query is what makes macOS ask for Automation.
    func authorize() async {
        defaults.set(true, forKey: Self.flagKey)
        access = .ready
        await poll()
        updatePolling()
    }

    func send(_ command: PlayerCommand) {
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
        if out.permissionDenied {
            access = .denied; snapshot = nil; artwork = nil
            cancelArtwork()
            onSnapshot?(nil)
            return
        }
        access = .ready
        snapshot = out.snapshot
        refreshArtwork()
        onSnapshot?(out.snapshot)
    }

    /// Never awaited by `poll()`: a slow cover must not stall the transport state. Each track key owns at
    /// most one fetch, and its result is assigned only while that key is still the current one.
    private func refreshArtwork() {
        guard let s = snapshot, let loader = artworkLoader else {
            artwork = nil
            cancelArtwork()
            return
        }
        let key = s.trackKey
        if artworkKey == key { return }
        cancelArtwork()
        artworkKey = key
        artwork = nil   // never show the previous track's cover
        let timeout = artworkTimeout
        artworkTask = Task { [weak self] in
            let data = await Self.fetch(loader, for: s, timeout: timeout)
            guard let self, !Task.isCancelled, self.artworkKey == key else { return }
            self.artwork = data
        }
    }

    private func cancelArtwork() {
        artworkTask?.cancel()
        artworkTask = nil
        artworkKey = nil
    }

    /// The loader against a clock: whichever finishes first wins, the other is cancelled.
    private nonisolated static func fetch(_ loader: any ArtworkLoading, for snap: NowPlayingSnapshot,
                                          timeout: Duration) async -> Data? {
        await withTaskGroup(of: Data?.self) { group in
            group.addTask { await loader.artwork(for: snap) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Keep polling while the island is closed so the music shows in its wing. Slower than the open tab:
    /// each poll is an AppleScript round trip. Still silent until the user pressed "Autoriser" once.
    func setBackground(_ on: Bool) {
        background = on
        updatePolling()
    }

    private func updatePolling() {
        task?.cancel()
        task = nil
        guard visible || background, access != .needsAuthorization else { return }
        task = Task { [weak self, interval] in
            while !Task.isCancelled {
                await self?.poll()
                let wait = (self?.visible ?? false) ? interval : .seconds(3)
                try? await Task.sleep(for: wait)
            }
        }
    }
}
