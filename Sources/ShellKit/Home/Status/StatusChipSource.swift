import Foundation

// FROZEN CONTRACT (MIS_0100, lot 1): other lanes implement `StatusChipSource`; do not change it without telling them.
//
// A source produces the reading of ONE chip kind and costs nothing until `start()`.
//
//  - The feed owns the lifecycle: it sets `onChange`, then calls `start()` when the island opens (and the chip is
//    enabled) and `stop()` when it closes or the chip is switched off. Both are idempotent.
//  - Between `start()` and `stop()` the source may sample (a poller, a listener, a reference-counted service). Outside
//    that window it does no work at all: no timer, no observer. Cadence is the source's business (2 s for CPU and
//    network, 60 s for the disk) and must carry leeway.
//  - `reading` is nil until the first value is known, and `stop()` sets it back to nil (a reopened island never shows
//    stale data). nil means "no chip".
//  - Whenever `reading` changes, the source calls `onChange?()` on the main actor, and only then: the feed redraws on
//    that call, so a source compares before it calls.
//  - Everything is main-actor: sample off the main thread if needed, then hop back to assign `reading`.
//  - One source per kind. If two sources claim a kind, the one registered last wins.

/// Produces the reading of one `StatusChipKind` while the island is open.
@MainActor
public protocol StatusChipSource: AnyObject {
    /// The chip this source feeds.
    var kind: StatusChipKind { get }
    /// The latest reading, nil when there is nothing to show (not started, no data, not available).
    var reading: StatusChipReading? { get }
    /// Set by the feed. Call it (on the main actor) each time `reading` changed.
    var onChange: (@MainActor () -> Void)? { get set }
    /// Idempotent. Begins sampling and publishes the first reading as soon as it is known.
    func start()
    /// Idempotent. Stops every timer and listener and sets `reading` to nil.
    func stop()
}
