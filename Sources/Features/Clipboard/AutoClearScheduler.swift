import AppKit

/// Clears the pasteboard `delay` seconds after a change, but only if nothing newer was copied.
/// Meaning of `clipboardAutoClearDelaySeconds` in the old app is UNKNOWN; this is the literal reading.
@MainActor
final class AutoClearScheduler {
    private let pasteboard: NSPasteboard
    private var task: Task<Void, Never>?
    /// Called after a clear, so the watcher does not treat it as a user copy.
    var didClear: () -> Void = {}

    init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    func schedule(delaySeconds: TimeInterval, expectedChangeCount: Int) {
        task?.cancel()
        task = nil
        guard let delay = AutoClearPolicy.effectiveDelay(delaySeconds) else { return }
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            if AutoClearPolicy.shouldClear(expectedChangeCount: expectedChangeCount,
                                           currentChangeCount: self.pasteboard.changeCount) {
                self.pasteboard.clearContents()
                self.didClear()
            }
        }
    }

    func cancel() { task?.cancel(); task = nil }
}
