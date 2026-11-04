import Foundation
import Testing
@testable import ClaudeLiveKit

/// A sleep that only ends when the test says so, and that records every duration it was asked for.
final class ManualSleeper: @unchecked Sendable {
    private struct Waiter { let id: Int; let duration: Duration; let continuation: CheckedContinuation<Void, Error> }
    private let lock = NSLock()
    private var waiters: [Waiter] = []
    private var nextID = 0
    private var asked: [Duration] = []

    func sleep(_ duration: Duration) async throws {
        let id = lock.withLock { () -> Int in nextID += 1; return nextID }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.withLock { waiters.append(Waiter(id: id, duration: duration, continuation: continuation)); asked.append(duration) }
                if Task.isCancelled { cancel(id) }
            }
        } onCancel: { cancel(id) }
    }

    private func cancel(_ id: Int) {
        let hit = lock.withLock { () -> Waiter? in
            guard let index = waiters.firstIndex(where: { $0.id == id }) else { return nil }
            return waiters.remove(at: index)
        }
        hit?.continuation.resume(throwing: CancellationError())
    }

    var pending: [Duration] { lock.withLock { waiters.map(\.duration) } }
    var everAsked: [Duration] { lock.withLock { asked } }

    @discardableResult
    func release(_ duration: Duration) -> Bool {
        let hit = lock.withLock { () -> Waiter? in
            guard let index = waiters.firstIndex(where: { $0.duration == duration }) else { return nil }
            return waiters.remove(at: index)
        }
        hit?.continuation.resume()
        return hit != nil
    }
}

final class FakeWatcher: ClaudeFileWatching, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?
    private(set) var watchCalls = 0
    private(set) var stopCalls = 0
    func watch(_ paths: [String], onEvent: @escaping @Sendable () -> Void) {
        lock.withLock { handler = onEvent; watchCalls += 1 }
    }
    func stop() { lock.withLock { stopCalls += 1; handler = nil } }
    func fire() { let h = lock.withLock { handler }; h?() }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var value: Int { lock.withLock { n } }
    func bump() { lock.withLock { n += 1 } }
}

/// Polls with real short sleeps, up to 60 s: only a real failure waits that long.
@MainActor
private func eventually(_ what: String = "", _ condition: () -> Bool) async -> Bool {
    for _ in 0..<3000 where !condition() { try? await Task.sleep(for: .milliseconds(20)) }
    return condition()
}

@Suite @MainActor struct ClaudeLiveEventDrivenTests {
    private func working() -> ClaudeSession { ClaudeSession(id: "a", pid: 1, state: .working, folderName: "demo") }

    private func make(sessions: [ClaudeSession], hasCandidates: Bool = true, reads: Counter, watcher: FakeWatcher,
                      sleeper: ManualSleeper, sink: RecordingSink? = nil) -> ClaudeLiveMonitor {
        ClaudeLiveMonitor(
            snapshot: { reads.bump(); return sessions },
            watchPaths: { ["/fake/sessions"] },
            hasCandidates: { hasCandidates },
            watcher: watcher,
            sink: sink,
            sleep: { try await sleeper.sleep($0) })
    }

    @Test func oneSharedInstanceForEveryConsumer() {
        #expect(ClaudeLiveMonitor.shared === ClaudeLiveMonitor.shared)
    }

    @Test func fileEventTriggersOneRefreshAfterTheDebounce() async {
        let reads = Counter(), watcher = FakeWatcher(), sleeper = ManualSleeper()
        let monitor = make(sessions: [], reads: reads, watcher: watcher, sleeper: sleeper)
        monitor.acquire("a")
        #expect(await eventually { reads.value == 1 && sleeper.pending == [.seconds(120)] })

        watcher.fire(); watcher.fire(); watcher.fire()   // a burst of writes
        #expect(await eventually { sleeper.pending.contains(.milliseconds(250)) })
        #expect(sleeper.pending.filter { $0 == .milliseconds(250) }.count == 1, "the burst coalesces into one wait")
        #expect(reads.value == 1, "nothing is read before the debounce ends")

        sleeper.release(.milliseconds(250))
        #expect(await eventually { reads.value == 2 })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(reads.value == 2, "exactly one refresh for the burst")
        monitor.release("a")
    }

    @Test func nothingIsReadWhileTheSessionsFolderIsEmpty() async {
        let reads = Counter(), watcher = FakeWatcher(), sleeper = ManualSleeper()
        let monitor = make(sessions: [], hasCandidates: false, reads: reads, watcher: watcher, sleeper: sleeper)
        monitor.acquire("a")
        #expect(await eventually { sleeper.pending == [.seconds(120)] })
        let armed = watcher.watchCalls
        for _ in 0..<3 {
            sleeper.release(.seconds(120))
            #expect(await eventually { sleeper.pending == [.seconds(120)] })
        }
        #expect(reads.value == 0, "no snapshot read without a session file")
        #expect(watcher.watchCalls >= armed + 3, "the folder is re-armed at every slow tick: it may appear later")
        monitor.release("a")
    }

    @Test func onlyTheSlowPollRunsWithoutEvents() async {
        let reads = Counter(), watcher = FakeWatcher(), sleeper = ManualSleeper()
        let monitor = make(sessions: [working()], reads: reads, watcher: watcher, sleeper: sleeper)
        monitor.acquire("a")
        #expect(await eventually { reads.value == 1 && sleeper.pending == [.seconds(30)] })
        sleeper.release(.seconds(30))
        #expect(await eventually { reads.value == 2 && sleeper.pending == [.seconds(30)] })
        #expect(Set(sleeper.everAsked) == [.seconds(30)], "no 2 s loop, no other timer")
        monitor.release("a")
    }

    @Test func theMonitorStopsWithItsLastConsumer() async {
        let reads = Counter(), watcher = FakeWatcher(), sleeper = ManualSleeper(), sink = RecordingSink()
        let monitor = make(sessions: [working()], reads: reads, watcher: watcher, sleeper: sleeper, sink: sink)
        monitor.acquire("shell")
        monitor.acquire("tab")
        monitor.acquire("tab")   // a name counts once
        #expect(await eventually { reads.value == 1 && !sink.live.isEmpty })

        monitor.release("tab")
        #expect(watcher.stopCalls == 0, "the shell still needs it")
        #expect(!sink.live.isEmpty)

        monitor.release("shell")
        #expect(watcher.stopCalls == 1)
        #expect(sink.live.isEmpty)
        #expect(monitor.sessions.isEmpty)
        #expect(await eventually { sleeper.pending.isEmpty }, "the slow loop is cancelled")
        watcher.fire()   // a late event must not restart anything
        try? await Task.sleep(for: .milliseconds(100))
        #expect(sleeper.pending.isEmpty)
        #expect(reads.value == 1)
    }

    @Test func aHostileFileIsNeverWatchedNorRead() throws {
        let dir = TempDir()
        dir.write("4242.json", Fixture.sessionJSON())
        dir.write("x.key", "{}")
        dir.write("12345678.json", Fixture.sessionJSON())          // 8 digits
        dir.write("-1.json", Fixture.sessionJSON())
        dir.write("a b.json", Fixture.sessionJSON())
        dir.write("9.json", Fixture.sessionJSON(status: "busy") + String(repeating: " ", count: 20_000))   // over 16 KB
        let reader = Fixture.reader(dir, alive: [4242: Fixture.start, 9: Fixture.start])
        let source = ClaudeLiveSource(reader: reader, hooks: nil)
        let paths = source.watchPaths()
        #expect(paths.contains(dir.url.path))
        #expect(paths.contains(dir.url.appendingPathComponent("4242.json").path))
        #expect(!paths.contains { $0.hasSuffix("x.key") || $0.hasSuffix("12345678.json") || $0.hasSuffix("-1.json") || $0.hasSuffix("a b.json") })
        #expect(source.hasCandidates())
        #expect(source.snapshot().map(\.pid) == [4242], "an oversized file is still skipped")
    }

    @Test func anEmptyFolderHasNoCandidates() {
        let dir = TempDir()
        dir.write("notes.txt", "x")
        let source = ClaudeLiveSource(reader: Fixture.reader(dir), hooks: nil)
        #expect(!source.hasCandidates())
    }
}
