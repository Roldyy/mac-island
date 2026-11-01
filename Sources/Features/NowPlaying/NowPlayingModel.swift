import AppKit
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
    /// Why the last reading (or the last silent permission check) failed, nil when it did not. The Home card
    /// prints its `line`; the unified log gets the same line (player, kind, number: never a title).
    private(set) var fault: NowPlayingFault?

    private static let flagKey = "nowplaying.automationRequested"
    private let providers: [any NowPlayingProvider]
    private var aggregator: NowPlayingAggregator
    private let defaults: any NowPlayingFlagStore
    private let artworkTimeout: Duration
    /// A reading that has not come back by then is a fault (-1712), not an endless wait.
    private let pollTimeout: Duration
    /// While the permission is missing and the Home is open: how often the silent check runs.
    static let permissionCheckInterval: Duration = .seconds(3)
    /// Players whose Automation permission was confirmed silently since the app started. A remembered
    /// permission is verified once per player, never on a timer.
    private var confirmedPlayers: Set<String> = []
    private let interval: Duration
    private let transport: NowPlayingTransport?
    private let artworkLoader: (any ArtworkLoading)?
    private let automation: (any AutomationChecking)?
    private let running: (any RunningAppChecking)?
    private let openPane: @MainActor (URL) -> Void
    private let sleep: @Sendable (Duration) async -> Void
    private var visible = false
    private var background = false
    /// The island home is open: the same fast polling as the tab, whatever the closed island has to show.
    private var homeOpen = false
    /// Called after every poll with what is playing (nil when nothing or access missing). The closed island listens.
    var onSnapshot: ((NowPlayingSnapshot?) -> Void)?
    /// Called after every reading and every change of access. The Home card listens.
    private var observers: [@MainActor () -> Void] = []
    private var task: Task<Void, Never>?
    private var artworkKey: String?
    private var artworkTask: Task<Void, Never>?

    init(providers: [any NowPlayingProvider], defaults: any NowPlayingFlagStore = UserDefaults.standard,
                interval: Duration = .seconds(1), transport: NowPlayingTransport?, artwork: (any ArtworkLoading)?,
         artworkTimeout: Duration = .seconds(5), pollTimeout: Duration = .seconds(8),
         automation: (any AutomationChecking)? = nil, running: (any RunningAppChecking)? = nil,
         openPane: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
         sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.pollTimeout = pollTimeout
        self.automation = automation
        self.running = running
        self.openPane = openPane
        self.sleep = sleep
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
            transport: NowPlayingTransport(runner: runner), artwork: ArtworkLoader(),
            automation: LiveAutomationChecker(), running: WorkspaceRunningChecker())
    }

    /// The first known player that is open (Spotify before Music), nil when none or no checker.
    var runningPlayerBundleID: String? {
        guard let running else { return nil }
        return [BundleIDs.spotify, BundleIDs.music].first { running.isRunning(bundleID: $0) }
    }

    func addObserver(_ observer: @escaping @MainActor () -> Void) { observers.append(observer) }

    private func notify() { for observer in observers { observer() } }

    /// The island home opened (true) or closed (false). Open: read now, poll every `interval`; closed: back to
    /// the slow background poll (or none).
    func setHomeOpen(_ open: Bool) {
        guard open != homeOpen else { return }
        homeOpen = open
        updatePolling()
    }

    /// Reads now. Before the user ever pressed "Autoriser", asks macOS WITHOUT prompting whether the permission
    /// already stands (a previous build, System Settings): if it does the model starts reading by itself.
    func refreshNow() async {
        var refused = false
        if let automation, let id = runningPlayerBundleID, needsSilentCheck(id) {
            // A TCC round trip: never on the main thread.
            let status = await Task.detached { automation.status(bundleID: id, askUser: false) }.value
            applySilent(status, id: id)
            refused = access == .denied   // macOS just said no: an Apple Event would only repeat it
        }
        guard access != .needsAuthorization, !refused else { notify(); return }
        await poll()
    }

    /// The silent check runs while no permission is on record (that is what it looks for), and once per player
    /// for a permission that is (a build re-signed, a reset in System Settings: macOS would prompt from the
    /// poll, and a prompt must only follow a click). Never for a refused one: the poll sees the grant itself.
    private func needsSilentCheck(_ id: String) -> Bool {
        switch access {
        case .needsAuthorization: true
        case .ready: !confirmedPlayers.contains(id)
        case .denied: false
        }
    }

    private func applySilent(_ status: AutomationStatus, id: String) {
        switch status {
        case .granted:
            confirmedPlayers.insert(id)
            setFault(nil)
            if access != .ready {
                defaults.set(true, forKey: Self.flagKey)
                access = .ready
                updatePolling()
            }
        case .denied:
            confirmedPlayers.remove(id)
            setFault(NowPlayingFault(.permissionDenied, bundleID: id))
            access = .denied
            snapshot = nil
            updatePolling()
            notify()
        case .notAsked:
            // Never asked (or reset): only the user's click may ask, so the card offers it.
            confirmedPlayers.remove(id)
            setFault(NowPlayingFault(.consentRequired, bundleID: id))
            if access == .ready {
                defaults.set(false, forKey: Self.flagKey)
                access = .needsAuthorization
                snapshot = nil
                updatePolling()
            }
        case .notRunning:
            // NSWorkspace says the player is open, macOS says it is not: show that, do not call it "empty".
            setFault(NowPlayingFault(player: PlayerNames.name(for: id), kind: .automation, code: Int(procNotFound)))
        case .failed(let code):
            setFault(NowPlayingFault(player: PlayerNames.name(for: id), kind: .automation, code: code))
        case .unknown:
            setFault(NowPlayingFault(player: PlayerNames.name(for: id), kind: .automation))
        }
    }

    private func setFault(_ new: NowPlayingFault?) {
        guard new != fault else { return }
        fault = new
        if let new { NowPlayingLog.record(new) }
    }

    /// The "Autoriser le contrôle de ..." click: the ONLY place the Automation prompt is triggered. Already
    /// refused: opens the Automation pane of System Settings instead (macOS never asks twice).
    func requestAutomation() async {
        guard let automation, let id = runningPlayerBundleID else { return }
        let status = await Task.detached { automation.status(bundleID: id, askUser: true) }.value
        switch status {
        case .granted:
            confirmedPlayers.insert(id)
            setFault(nil)
            await authorize()
        case .denied:
            setFault(NowPlayingFault(.permissionDenied, bundleID: id))
            access = .denied
            updatePolling()   // a permission switched on in System Settings is picked up by the next poll
            notify()
            openPane(AutomationPane.url)
        case .notAsked, .notRunning, .unknown, .failed:
            applySilent(status, id: id)
            notify()
        }
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
        // An open player with nothing loaded still gets its own play command, not a media key (which could wake Music).
        let source = snapshot?.sourceBundleID ?? runningPlayerBundleID
        guard let transport else { return }
        Task { [weak self] in
            await transport.send(command, source: source)
            try? await Task.sleep(for: .milliseconds(250))
            await self?.poll()
        }
    }

    func poll() async {
        let providers = self.providers
        let gathered = await Deadline.run(pollTimeout) { await NowPlayingAggregator.gather(from: providers) }
            ?? timedOutRound()
        let out = aggregator.resolve(gathered)
        if out.permissionDenied {
            setFault(out.fault)
            access = .denied; snapshot = nil; artwork = nil
            cancelArtwork()
            onSnapshot?(nil)
            notify()
            return
        }
        if out.consentRequired {
            // The script itself says the permission was never asked: back to the click, no prompt from a poll.
            setFault(out.fault)
            defaults.set(false, forKey: Self.flagKey)
            access = .needsAuthorization; snapshot = nil; artwork = nil
            cancelArtwork()
            onSnapshot?(nil)
            updatePolling()
            notify()
            return
        }
        access = .ready
        setFault(out.fault)
        snapshot = out.snapshot
        refreshArtwork()
        onSnapshot?(out.snapshot)
        notify()
    }

    /// What a round that outlived `pollTimeout` stands for: the open player did not answer (-1712).
    private func timedOutRound() -> NowPlayingAggregator.Gathered {
        let id = runningPlayerBundleID ?? providers.first?.bundleID ?? BundleIDs.spotify
        return NowPlayingAggregator.Gathered(faults: [NowPlayingFault(.timedOut, bundleID: id)])
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
            self.notify()   // the cover arrived after the poll that announced the track
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
        guard visible || homeOpen || (background && access == .ready) else { return }
        if access == .needsAuthorization {
            // Nothing is read before the user agrees, but while the home is open a player that was just launched,
            // or a permission granted elsewhere, must show up: a silent check (no prompt, off the main thread)
            // every few seconds, and only while that card is on screen. Closed: nothing runs, no TCC call at all.
            guard homeOpen else { return }
            task = Task { [weak self, sleep] in
                while !Task.isCancelled {
                    await self?.refreshNow()
                    await sleep(Self.permissionCheckInterval)
                }
            }
            return
        }
        task = Task { [weak self, interval, sleep] in
            while !Task.isCancelled {
                await self?.poll()
                let fast = self.map { $0.visible || $0.homeOpen } ?? false
                await sleep(fast ? interval : .seconds(3))
            }
        }
    }
}
