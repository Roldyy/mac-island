import Combine
import Foundation

/// Published Claude status, polled once a second while a terminal session exists.
@MainActor
public final class ClaudeStatusModel: ObservableObject {
    @Published public private(set) var status: ClaudeStatus = .idle

    private var tracker = ClaudeStatusTracker()
    private var timer: Timer?

    public init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    deinit { timer?.invalidate() }

    private func poll() {
        let session = TerminalSession.shared
        guard session.hasSession else {
            // No shell: nothing can run. Let the tracker settle on idle/done without scanning processes.
            apply(tracker.update(claudeRunning: false, lastOutputAt: .distantPast))
            return
        }
        let running = ProcessTree.containsClaude(below: session.shellPid)
        apply(tracker.update(claudeRunning: running, lastOutputAt: session.lastOutputAt))
    }

    private func apply(_ new: ClaudeStatus) {
        if new != status { status = new }
    }
}
