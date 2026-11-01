import Foundation

/// Runs `work` against a clock and returns whichever finishes first: its value, or nil once `timeout` passed.
/// Unlike a task group this does not wait for the loser: a script queue stuck on a hung player cannot hold
/// the caller. The abandoned work is cancelled; it ends whenever the player finally answers.
enum Deadline {
    static func run<T: Sendable>(_ timeout: Duration, _ work: @escaping @Sendable () async -> T) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let gate = Gate(continuation)
            let job = Task { gate.finish(await work()) }
            Task {
                try? await Task.sleep(for: timeout)
                if gate.finish(nil) { job.cancel() }
            }
        }
    }

    /// Resumes the continuation exactly once, whoever gets there first.
    private final class Gate<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T?, Never>?

        init(_ continuation: CheckedContinuation<T?, Never>) { self.continuation = continuation }

        @discardableResult
        func finish(_ value: T?) -> Bool {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            guard let pending else { return false }
            pending.resume(returning: value)
            return true
        }
    }
}
