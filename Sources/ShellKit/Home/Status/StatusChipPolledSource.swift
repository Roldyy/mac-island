import Foundation

/// Shared plumbing of the built-in chips: the reading, the change callback and the start/stop rules of the
/// `StatusChipSource` contract. A subclass builds its poller in `begin()` and cancels it in `end()`; samples are
/// taken off the main thread and handed to `publish`, which assigns only a changed reading.
@MainActor
class StatusChipPolledSource: StatusChipSource {
    let kind: StatusChipKind
    private(set) var reading: StatusChipReading?
    var onChange: (@MainActor () -> Void)?
    private(set) var isRunning = false

    init(kind: StatusChipKind) { self.kind = kind }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        begin()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        end()
        reading = nil
    }

    /// Subclass hook: start the poller and any listener.
    func begin() {}
    /// Subclass hook: cancel the poller and every listener.
    func end() {}

    /// Assigns `new` when it differs and the source is running (a late sample after `stop()` is dropped).
    func publish(_ new: StatusChipReading?) {
        guard isRunning, new != reading else { return }
        reading = new
        onChange?()
    }

    /// A poller `sleep` with leeway, so the system can coalesce the wake-ups.
    nonisolated static func sleeper(tolerance: Duration) -> @Sendable (Duration) async throws -> Void {
        { try await Task.sleep(for: $0, tolerance: tolerance) }
    }
}
