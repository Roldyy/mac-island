import AppKit
import IslandKit

/// Clears the pasteboard `delay` seconds after a change, but only if nothing newer was copied.
/// Meaning of `clipboardAutoClearDelaySeconds` in the old app is UNKNOWN; this is the literal reading.
/// The count check and the clear run together on the `GeneralPasteboardLane` (never on the main thread, never beside
/// another read of the general pasteboard); `didClear` is called on main afterwards with the
/// change count read in the SAME lane block as the clear (a copy made after it is then a change, never adopted as ours).
@MainActor
final class AutoClearScheduler {
    private let pasteboard: NSPasteboard
    private let lane: GeneralPasteboardLane
    private var task: Task<Void, Never>?
    /// Called after a clear with the count the clear produced, so the watcher does not treat it as a user copy.
    var didClear: (_ changeCount: Int) -> Void = { _ in }

    init(pasteboard: NSPasteboard, lane: GeneralPasteboardLane = .shared) {
        self.pasteboard = pasteboard
        self.lane = lane
    }

    func schedule(delaySeconds: TimeInterval, expectedChangeCount: Int) {
        task?.cancel()
        task = nil
        guard let delay = AutoClearPolicy.effectiveDelay(delaySeconds) else { return }
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            let pasteboard = self.pasteboard
            self.lane.async({ () -> Int? in
                guard AutoClearPolicy.shouldClear(expectedChangeCount: expectedChangeCount,
                                                  currentChangeCount: pasteboard.changeCount) else { return nil }
                pasteboard.clearContents()
                return pasteboard.changeCount
            }, then: { [weak self] clearedCount in
                guard let clearedCount else { return }
                MainActor.assumeIsolated { self?.didClear(clearedCount) }
            })
        }
    }

    func cancel() { task?.cancel(); task = nil }
}
