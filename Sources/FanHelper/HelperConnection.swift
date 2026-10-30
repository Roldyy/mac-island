import FanShared
import Foundation

/// Exported object for one accepted client connection. Every call is forwarded to the daemon's
/// serial queue; payloads are decoded with `FanWire` (size-capped JSON), never as objects.
final class HelperConnection: NSObject, FanHelperXPC, @unchecked Sendable {
    private let daemon: HelperDaemon
    let clientID: Int
    /// Set by `hello` with a matching protocol version. Manual requests need it; automatic does not.
    private var versionAgreed = false

    init(daemon: HelperDaemon, clientID: Int) {
        self.daemon = daemon
        self.clientID = clientID
    }

    func hello(clientVersion: Int, reply: @escaping @Sendable (Int) -> Void) {
        daemon.onQueue { versionAgreed = clientVersion == FanHelperContract.protocolVersion }
        reply(FanHelperContract.protocolVersion)
    }

    func fetchState(reply: @escaping @Sendable (Data?, String?) -> Void) {
        let state = daemon.onQueue { daemon.core.state() }
        Self.send(state, reply)
    }

    func perform(command: Data, reply: @escaping @Sendable (Data?, String?) -> Void) {
        let decoded: FanCommand
        do {
            decoded = try FanWire.decode(FanCommand.self, from: command)
        } catch {
            reply(nil, "badCommand")
            return
        }
        let result: FanCommandResult = daemon.onQueue {
            if case .setTarget = decoded, !versionAgreed {
                return FanCommandResult(status: .rejected, reason: "protocolVersion")
            }
            return daemon.core.perform(decoded, client: clientID)
        }
        daemon.log(result: result, client: clientID)
        Self.send(result, reply)
    }

    func heartbeat(reply: @escaping @Sendable (Bool) -> Void) {
        reply(daemon.onQueue { daemon.core.heartbeat(client: clientID) })
    }

    func selfTestReadOnly(reply: @escaping @Sendable (Data?, String?) -> Void) {
        let report = daemon.onQueue { daemon.core.selfTestReadOnly() }
        Self.send(report, reply)
    }

    private static func send<T: Encodable>(_ value: T, _ reply: @Sendable (Data?, String?) -> Void) {
        do { reply(try FanWire.encode(value), nil) } catch { reply(nil, "encodeFailed") }
    }
}
