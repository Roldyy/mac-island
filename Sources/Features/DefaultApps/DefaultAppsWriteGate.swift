import Foundation

/// One mutual exclusion for every LaunchServices write of the feature (apply, undo, guard pass). First come, first
/// served; whoever holds it runs to the end of its loop, so a guard pass can never re-apply a replacement in the
/// middle of an undo, and an undo never starts while the guard is writing.
@MainActor
public final class DefaultAppsWriteGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    nonisolated public init() {}

    public var isBusy: Bool { busy }

    public func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    public func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }
}
