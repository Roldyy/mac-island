import FanShared
import Foundation

/// NSXPC client of the root helper.
///
/// - `.privileged`: the helper is a launchd daemon in the system bootstrap.
/// - `setCodeSigningRequirement` (macOS 13+): the app only talks to a helper signed by team
///   U3TUL63HHK with identifier `be.roldy.macisland.fanhelper`; anything else invalidates.
/// - Reconnect: after an interruption (helper exited or crashed) or an invalidation, `hello` is
///   sent again with `ReconnectBackoff` while the feature is started. Sending it is also what
///   makes launchd relaunch a crashed helper, whose startup recovery restores automatic mode.
/// - Every call times out after `callTimeout` so a stuck helper cannot hang the island.
///
/// COMPILE-ONLY in this lane: it needs the signed bundle and the approved daemon to connect.
final class FanXPCClient: FanHelperClient, @unchecked Sendable {
    static let callTimeout: TimeInterval = 3

    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private var backoff = ReconnectBackoff()
    private var wantsConnection = false
    private var reconnectScheduled = false
    private var reachabilityHandler: (@Sendable (Bool) -> Void)?

    var onReachabilityChanged: (@Sendable (Bool) -> Void)? {
        get { locked { reachabilityHandler } }
        set { locked { reachabilityHandler = newValue } }
    }

    func connect() async -> Bool {
        locked { wantsConnection = true }
        do {
            let version: Int = try await call { proxy, done in
                proxy.hello(clientVersion: FanHelperContract.protocolVersion) { done(.success($0)) }
            }
            guard version == FanHelperContract.protocolVersion else { throw FanClientError.versionMismatch(version) }
            locked { backoff.reset() }
            return true
        } catch {
            scheduleReconnect()
            return false
        }
    }

    func perform(_ command: FanCommand) async throws -> FanCommandResult {
        let payload = try FanWire.encode(command)
        let data: Data = try await call { proxy, done in
            proxy.perform(command: payload) { data, message in
                done(data.map { .success($0) } ?? .failure(FanClientError.helper(message ?? "noReply")))
            }
        }
        return try FanWire.decode(FanCommandResult.self, from: data)
    }

    func heartbeat() async -> Bool {
        (try? await call { proxy, done in proxy.heartbeat { done(.success($0)) } }) ?? false
    }

    func fetchState() async throws -> FanState {
        let data: Data = try await call { proxy, done in
            proxy.fetchState { data, message in
                done(data.map { .success($0) } ?? .failure(FanClientError.helper(message ?? "noReply")))
            }
        }
        return try FanWire.decode(FanState.self, from: data)
    }

    func sendAllAutomaticBlocking(timeout: TimeInterval) {
        guard let conn = locked({ connection }), let payload = try? FanWire.encode(FanCommand.allAutomatic) else { return }
        let done = DispatchSemaphore(value: 0)
        let proxy = conn.remoteObjectProxyWithErrorHandler { _ in done.signal() } as? FanHelperXPC
        guard let proxy else { return }
        proxy.perform(command: payload) { _, _ in done.signal() }
        _ = done.wait(timeout: .now() + timeout)
    }

    func disconnect() {
        let conn: NSXPCConnection? = locked {
            wantsConnection = false
            defer { connection = nil }
            return connection
        }
        conn?.invalidate()
    }

    // MARK: - Connection

    private func currentConnection() -> NSXPCConnection {
        lock.lock(); defer { lock.unlock() }
        if let connection { return connection }
        let conn = NSXPCConnection(machServiceName: FanHelperContract.machServiceName, options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: FanHelperXPC.self)
        conn.setCodeSigningRequirement(FanHelperContract.helperRequirement)
        conn.interruptionHandler = { [weak self, weak conn] in self?.dropped(conn, invalidated: false) }
        conn.invalidationHandler = { [weak self, weak conn] in self?.dropped(conn, invalidated: true) }
        conn.activate()
        connection = conn
        return conn
    }

    private func dropped(_ conn: NSXPCConnection?, invalidated: Bool) {
        let handler: (@Sendable (Bool) -> Void)? = locked {
            if invalidated, let conn, connection === conn { connection = nil }
            return reachabilityHandler
        }
        handler?(false)
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        let delay: TimeInterval? = locked {
            guard wantsConnection, !reconnectScheduled else { return nil }
            reconnectScheduled = true
            return backoff.next()
        }
        guard let delay else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            let wanted: Bool = self.locked {
                self.reconnectScheduled = false
                return self.wantsConnection
            }
            guard wanted else { return }
            Task {
                if await self.connect() { self.onReachabilityChanged?(true) }
            }
        }
    }

    /// One XPC round trip with a timeout. Exactly one of reply, error handler or timeout resumes.
    private func call<T: Sendable>(
        _ body: @escaping (FanHelperXPC, @escaping @Sendable (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        let conn = currentConnection()
        return try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in once.resume(.failure(error)) } as? FanHelperXPC
            guard let proxy else {
                once.resume(.failure(FanClientError.noProxy))
                return
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.callTimeout) {
                once.resume(.failure(FanClientError.timeout))
            }
            body(proxy) { once.resume($0) }
        }
    }

    private func locked<T>(_ work: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return work()
    }
}

/// Resumes a continuation at most once, from whichever callback comes first.
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) { self.continuation = continuation }

    func resume(_ result: Result<T, Error>) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(with: result)
    }
}
