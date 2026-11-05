import AppKit
import IslandKit

/// Clears the pasteboard `delay` seconds after a change, but only if nothing newer was copied.
/// Meaning of `clipboardAutoClearDelaySeconds` in the old app is UNKNOWN; this is the literal reading.
/// The count check and the clear run together on the `GeneralPasteboardLane` (never on the main thread, never beside
/// another read of the general pasteboard); `didClear` is called on main afterwards.
@MainActor
final class AutoClearScheduler {
    private let pasteboard: NSPasteboard
    private let lane: GeneralPasteboardLane
    private var task: Task<Void, Never>?
    /// Called after a clear, so the watcher does not treat it as a user copy.
    var didClear: () -> Void = {}

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
            self.lane.async({
                guard AutoClearPolicy.shouldClear(expectedChangeCount: expectedChangeCount,
                                                  currentChangeCount: pasteboard.changeCount) else { return false }
                pasteboard.clearContents()
                return true
            }, then: { [weak self] cleared in
                guard cleared else { return }
                MainActor.assumeIsolated { self?.didClear() }
            })
        }
    }

    func cancel() { task?.cancel(); task = nil }
}
