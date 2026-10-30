import FanShared
import Foundation
@testable import FansFeature

/// Records every command; never talks to a real helper.
final class FakeHelperClient: FanHelperClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _commands: [FanCommand] = []
    private var _blockingAutomatic = 0
    private var _heartbeats = 0
    private var _disconnects = 0
    private var held: [CheckedContinuation<Void, Never>] = []
    private var heldWaiter: CheckedContinuation<Void, Never>?
    var reachable = true
    var heartbeatAnswer = true
    /// When true, a `setTarget` stays in flight until `releaseHeld()` (late-reply tests).
    var holdSetTarget = false
    var state = FanState(protocolVersion: 1, fans: [], maxTemperatureCelsius: 60, manualActive: false)
    var result: (FanCommand) -> FanCommandResult = { command in
        switch command {
        case .setTarget(let fan, let rpm): FanCommandResult(status: .applied, fan: fan, appliedRPM: rpm)
        case .automatic(let fan): FanCommandResult(status: .automatic, fan: fan)
        case .allAutomatic: FanCommandResult(status: .automatic)
        }
    }
    var onReachabilityChanged: (@Sendable (Bool) -> Void)?

    var commands: [FanCommand] { lock.lock(); defer { lock.unlock() }; return _commands }
    var blockingAutomatic: Int { lock.lock(); defer { lock.unlock() }; return _blockingAutomatic }
    var heartbeats: Int { lock.lock(); defer { lock.unlock() }; return _heartbeats }
    var disconnects: Int { lock.lock(); defer { lock.unlock() }; return _disconnects }

    func connect() async -> Bool { reachable }

    func perform(_ command: FanCommand) async throws -> FanCommandResult {
        withLock { _commands.append(command) }
        if case .setTarget = command, holdSetTarget {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                var waiter: CheckedContinuation<Void, Never>?
                withLock {
                    held.append(c)
                    waiter = heldWaiter
                    heldWaiter = nil
                }
                waiter?.resume()
            }
        }
        guard reachable else { throw FanClientError.timeout }
        return result(command)
    }

    /// Returns once a held `setTarget` is in flight.
    func waitUntilHeld() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            var ready = false
            withLock {
                if held.isEmpty { heldWaiter = c } else { ready = true }
            }
            if ready { c.resume() }
        }
    }

    /// Lets every held `setTarget` reply.
    func releaseHeld() {
        var all: [CheckedContinuation<Void, Never>] = []
        withLock {
            all = held
            held.removeAll()
        }
        all.forEach { $0.resume() }
    }

    func heartbeat() async -> Bool {
        withLock { _heartbeats += 1 }
        return reachable && heartbeatAnswer
    }

    func fetchState() async throws -> FanState {
        guard reachable else { throw FanClientError.timeout }
        return state
    }

    func sendAllAutomaticBlocking(timeout: TimeInterval) {
        withLock { _blockingAutomatic += 1 }
    }

    func disconnect() {
        withLock { _disconnects += 1 }
    }

    /// Synchronous so it can be called from the async methods above.
    private func withLock(_ body: () -> Void) {
        lock.lock(); defer { lock.unlock() }
        body()
    }

    /// Simulates the XPC connection dropping (helper crash or invalidation).
    func dropConnection() { onReachabilityChanged?(false) }
}

final class FakeInstaller: FanHelperInstalling {
    var status: HelperInstallStatus = .enabled
    var statusAfterRegister: HelperInstallStatus = .requiresApproval
    var registerError: Error?
    private(set) var registerCount = 0
    private(set) var openSettingsCount = 0

    func register() throws {
        registerCount += 1
        if let registerError { throw registerError }
        status = statusAfterRegister
    }

    func openLoginItems() { openSettingsCount += 1 }
}

@MainActor
final class FakeHeartbeat: HeartbeatScheduling {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var interval: TimeInterval?
    private var beat: (@MainActor () async -> Void)?
    var isRunning: Bool { beat != nil }

    nonisolated init() {}

    func start(every interval: TimeInterval, _ beat: @escaping @MainActor () async -> Void) {
        guard self.beat == nil else { return }
        startCount += 1
        self.interval = interval
        self.beat = beat
    }

    func stop() {
        if beat != nil { stopCount += 1 }
        beat = nil
    }

    /// Runs one heartbeat as the timer would.
    func fire() async { await beat?() }
}

final class FakeReadingSource: FanReadingSource, @unchecked Sendable {
    var fans: [FanReading] = [
        FanReading(index: 0, actualRPM: 2317, minRPM: 2317, maxRPM: 7826, targetRPM: 2317, mode: .automatic),
        FanReading(index: 1, actualRPM: 2499, minRPM: 2317, maxRPM: 7826, targetRPM: 2502, mode: .automatic),
    ]
    var error: Error?

    func readFans() throws -> [FanReading] {
        if let error { throw error }
        return fans
    }
}

struct FakeError: Error {}

@MainActor
func makeModel(client: FakeHelperClient = FakeHelperClient(), installer: FakeInstaller = FakeInstaller(),
               heartbeat: FakeHeartbeat = FakeHeartbeat(),
               source: FakeReadingSource = FakeReadingSource()) -> FansModel {
    FansModel(source: source, client: client, installer: installer, heartbeat: heartbeat)
}
