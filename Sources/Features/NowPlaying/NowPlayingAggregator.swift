import Foundation

/// Picks the active source: playing beats paused; among playing, the one that started most
/// recently; among paused, the one that played most recently; otherwise input order.
/// Pure apart from the injected clock.
public struct NowPlayingAggregator: Sendable {
    public struct Output: Sendable {
        public var snapshot: NowPlayingSnapshot?
        /// True only when nothing could be read and at least one provider was refused.
        public var permissionDenied: Bool
    }

    private let clock: @Sendable () -> Date
    private var wasPlaying: Set<String> = []
    private var startedPlaying: [String: Date] = [:]
    private var lastSeenPlaying: [String: Date] = [:]

    public init(clock: @escaping @Sendable () -> Date = { Date() }) {
        self.clock = clock
    }

    public mutating func select(from snapshots: [NowPlayingSnapshot]) -> NowPlayingSnapshot? {
        let now = clock()
        var playingNow: Set<String> = []
        for s in snapshots where s.isPlaying {
            playingNow.insert(s.sourceBundleID)
            if !wasPlaying.contains(s.sourceBundleID) { startedPlaying[s.sourceBundleID] = now }
            lastSeenPlaying[s.sourceBundleID] = now
        }
        wasPlaying = playingNow

        func rank(_ s: NowPlayingSnapshot) -> (Int, Date) {
            if s.isPlaying { return (1, startedPlaying[s.sourceBundleID] ?? now) }
            return (0, lastSeenPlaying[s.sourceBundleID] ?? .distantPast)
        }
        var best: NowPlayingSnapshot?
        for s in snapshots {
            guard let b = best else { best = s; continue }
            let (rs, rb) = (rank(s), rank(b))
            if rs.0 > rb.0 || (rs.0 == rb.0 && rs.1 > rb.1) { best = s }
        }
        return best
    }

    public static func gather(from providers: [any NowPlayingProvider]) async -> (snapshots: [NowPlayingSnapshot], denied: Bool) {
        var snaps: [NowPlayingSnapshot] = []
        var denied = false
        for p in providers {
            do {
                if let s = try await p.snapshot() { snaps.append(s) }
            } catch NowPlayingError.permissionDenied {
                denied = true
            } catch {
                continue
            }
        }
        return (snaps, denied)
    }

    public mutating func resolve(_ gathered: (snapshots: [NowPlayingSnapshot], denied: Bool)) -> Output {
        let chosen = select(from: gathered.snapshots)
        return Output(snapshot: chosen, permissionDenied: chosen == nil && gathered.denied)
    }

    public mutating func current(from providers: [any NowPlayingProvider]) async -> Output {
        resolve(await Self.gather(from: providers))
    }
}
