import Foundation

/// Repeats the heartbeat while manual control is active. Started on the first applied manual
/// target, stopped on every return to automatic.
@MainActor
protocol HeartbeatScheduling: AnyObject {
    var isRunning: Bool { get }
    /// No-op when already running.
    func start(every interval: TimeInterval, _ beat: @escaping @MainActor () async -> Void)
    func stop()
}

@MainActor
final class TaskHeartbeatScheduler: HeartbeatScheduling {
    private var task: Task<Void, Never>?

    var isRunning: Bool { task != nil }

    nonisolated init() {}

    func start(every interval: TimeInterval, _ beat: @escaping @MainActor () async -> Void) {
        guard task == nil else { return }
        task = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await beat()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
