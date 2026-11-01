import Foundation
import Observation

/// The seam between the Home card and whatever reads the players. The app wires these closures; the feed
/// knows nothing else (no feature module, nothing from the closed island).
public struct HomeNowPlayingSource {
    /// The latest reading, cheap and synchronous.
    public var read: @MainActor () -> HomeNowPlayingReading
    /// Reads the players now (and re-checks the permission). Called when the Home opens.
    public var refresh: @MainActor () async -> Void
    /// The Home is open (true) or closed (false): the source polls fast while it is open, and only then.
    public var setOpen: @MainActor (Bool) -> Void
    public var send: @MainActor (HomeTransport) -> Void
    /// The user clicked "Autoriser": the only place a permission prompt may be triggered.
    public var authorize: @MainActor () -> Void
    /// Registers a callback run after each reading.
    public var observe: @MainActor (@escaping @MainActor () -> Void) -> Void

    public init(read: @escaping @MainActor () -> HomeNowPlayingReading,
                refresh: @escaping @MainActor () async -> Void,
                setOpen: @escaping @MainActor (Bool) -> Void,
                send: @escaping @MainActor (HomeTransport) -> Void,
                authorize: @escaping @MainActor () -> Void,
                observe: @escaping @MainActor (@escaping @MainActor () -> Void) -> Void) {
        self.read = read
        self.refresh = refresh
        self.setOpen = setOpen
        self.send = send
        self.authorize = authorize
        self.observe = observe
    }

    /// Nothing behind it: the card shows the stored last track, transport keys post media keys.
    public static let inert = HomeNowPlayingSource(
        read: { .none }, refresh: {}, setOpen: { _ in },
        send: { MediaKeyPoster.post($0) }, authorize: {}, observe: { _ in })
}

/// Live state of the Home now-playing card. Assigns `state` only when it changes.
@MainActor @Observable
public final class HomeNowPlayingFeed {
    public private(set) var state: HomeNowPlayingState = .idle
    /// Called after each change of `state` (HomeModel mirrors it into `track` and the notice).
    @ObservationIgnored public var onChange: ((HomeNowPlayingState) -> Void)?
    @ObservationIgnored public private(set) var isOpen = false
    @ObservationIgnored private var source: HomeNowPlayingSource
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    public init(source: HomeNowPlayingSource = .inert) {
        self.source = source
    }

    /// Connects the real source and shows its current reading.
    public func attach(_ source: HomeNowPlayingSource) {
        self.source = source
        source.observe { [weak self] in self?.reload() }
        if isOpen { source.setOpen(true) }
        reload()
    }

    /// The island home opened or closed. Opening reads at once and starts the fast polling of the source;
    /// closing stops it. Repeating the same value does nothing.
    public func setOpen(_ open: Bool) {
        guard open != isOpen else { return }
        isOpen = open
        source.setOpen(open)
        refreshTask?.cancel()
        refreshTask = nil
        guard open else { return }
        reload()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.source.refresh()
            self.reload()
        }
    }

    public func send(_ command: HomeTransport) {
        source.send(command)
    }

    /// The "Autoriser le contrôle de ..." button.
    public func authorize() {
        source.authorize()
    }

    /// Re-reads the source's latest reading.
    public func reload() {
        let next = HomeNowPlayingState.resolve(source.read())
        guard next != state else { return }
        state = next
        onChange?(next)
    }
}
