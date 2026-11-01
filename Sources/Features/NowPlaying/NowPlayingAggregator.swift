import Foundation

/// Picks the active source: playing beats paused; among playing, the one that started most
/// recently; among paused, the one that played most recently; otherwise input order.
/// Pure apart from the injected clock.
struct NowPlayingAggregator: Sendable {
    struct Output: Sendable {
        var snapshot: NowPlayingSnapshot?
        /// True only when nothing could be read and at least one provider was refused.
        var permissionDenied: Bool
        /// True only when nothing could be read and a provider reports the permission was never asked.
        var consentRequired = false
        /// Why nothing could be read, when a provider failed (the first one). Nil with a snapshot.
        var fault: NowPlayingFault?
    }

    /// What one round over the providers returned.
    struct Gathered: Sendable {
        var snapshots: [NowPlayingSnapshot] = []
        var faults: [NowPlayingFault] = []
        var denied = false
        var consentRequired = false
    }

    private let clock: @Sendable () -> Date
    private var wasPlaying: Set<String> = []
    private var startedPlaying: [String: Date] = [:]
    private var lastSeenPlaying: [String: Date] = [:]

    init(clock: @escaping @Sendable () -> Date = { Date() }) {
        self.clock = clock
    }

    mutating func select(from snapshots: [NowPlayingSnapshot]) -> NowPlayingSnapshot? {
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

    /// Asks every provider. A failure is kept as a fault, never dropped: a player that is open and cannot be
    /// read is not a player with nothing loaded.
    static func gather(from providers: [any NowPlayingProvider]) async -> Gathered {
        var out = Gathered()
        for p in providers {
            do {
                if let s = try await p.snapshot() { out.snapshots.append(s) }
            } catch is CancellationError {
                continue
            } catch let error as NowPlayingError {
                out.faults.append(NowPlayingFault(error, bundleID: p.bundleID))
                if error == .permissionDenied { out.denied = true }
                if error == .consentRequired { out.consentRequired = true }
            } catch {
                out.faults.append(NowPlayingFault(.scriptFailed(code: (error as NSError).code), bundleID: p.bundleID))
            }
        }
        return out
    }

    mutating func resolve(_ gathered: Gathered) -> Output {
        let chosen = select(from: gathered.snapshots)
        let empty = chosen == nil
        return Output(snapshot: chosen,
                      permissionDenied: empty && gathered.denied,
                      consentRequired: empty && gathered.consentRequired && !gathered.denied,
                      fault: empty ? gathered.faults.first : nil)
    }

    mutating func current(from providers: [any NowPlayingProvider]) async -> Output {
        resolve(await Self.gather(from: providers))
    }
}
