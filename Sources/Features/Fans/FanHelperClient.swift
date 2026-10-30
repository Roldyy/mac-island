import FanShared
import Foundation

enum FanClientError: Error, Equatable {
    case timeout
    case noProxy
    case versionMismatch(Int)
    case helper(String)
}

/// App-side view of the root helper. `FanXPCClient` is the real one; tests use a fake.
protocol FanHelperClient: AnyObject, Sendable {
    /// Opens the connection if needed and checks the protocol version. True when the helper answered.
    func connect() async -> Bool
    func perform(_ command: FanCommand) async throws -> FanCommandResult
    /// False when the helper is unreachable or no longer holds manual mode for this app.
    func heartbeat() async -> Bool
    func fetchState() async throws -> FanState
    /// Automatic for every fan, callable from any thread (quit, deinit). Waits at most `timeout`
    /// for the reply and never opens a new connection: without one, nothing was set manual.
    func sendAllAutomaticBlocking(timeout: TimeInterval)
    /// Drops the connection and stops reconnecting.
    func disconnect()
    /// Called on any thread: false when the connection drops, true when a reconnect succeeds.
    var onReachabilityChanged: (@Sendable (Bool) -> Void)? { get set }
}
