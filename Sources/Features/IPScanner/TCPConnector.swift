import Foundation
import Network

/// How one TCP connection attempt ended.
public enum ConnectResult: Equatable, Sendable {
    case open(latencyMs: Double)
    /// An explicit refusal (RST): the host is up and the port is closed.
    case refused(latencyMs: Double)
    /// "No route to host" and its relatives: unresolved neighbour, or the system refusing local network access.
    case noRoute
    case timeout
    case failed

    public var hostIsUp: Bool {
        switch self {
        case .open, .refused: true
        default: false
        }
    }
}

/// The error classification the Local Network prompt relies on. Pure, so it is tested without a socket.
public enum LocalNetworkClassifier {
    /// kDNSServiceErr_PolicyDenied: what the Bonjour browser reports when local network access is refused.
    public static let dnsPolicyDenied: Int32 = -65570

    public static func isNoRoute(_ error: NWError) -> Bool {
        guard case .posix(let code) = error else { return false }
        return [.EHOSTUNREACH, .ENETUNREACH, .EPERM, .EACCES].contains(code)
    }

    public static func isPolicyDenial(_ error: NWError) -> Bool {
        if case .dns(let code) = error { return code == dnsPolicyDenied }
        return false
    }

    public static func result(for error: NWError, latencyMs: Double) -> ConnectResult? {
        if case .posix(let code) = error, code == .ECONNREFUSED { return .refused(latencyMs: latencyMs) }
        if isNoRoute(error) { return .noRoute }
        return nil
    }

    /// One first connection to a host that is certainly up (the gateway): answered means allowed, "no route" means
    /// refused, a silence proves nothing.
    public static func state(after result: ConnectResult) -> LocalNetworkState {
        if result.hostIsUp { return .granted }
        if result == .noRoute { return .denied }
        return .unknown
    }
}

/// One TCP connect through Network.framework, with a hard timeout and cooperative cancellation. Live code: never
/// called from a test.
enum TCPConnector {
    static func connect(to ip: IPv4Address, port: UInt16, timeout: Duration) async -> ConnectResult {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return .failed }
        let session = ConnectSession()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<ConnectResult, Never>) in
                session.begin(continuation, host: ip, port: nwPort, timeout: timeout)
            }
        } onCancel: {
            session.cancel()
        }
    }
}

private final class ConnectSession: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ConnectResult, Never>?
    private var connection: NWConnection?
    private var finished = false
    private var cancelledEarly = false
    private let queue = DispatchQueue(label: "be.roldy.macisland.ipscanner.connect", qos: .utility)

    func begin(_ continuation: CheckedContinuation<ConnectResult, Never>, host: IPv4Address, port: NWEndpoint.Port, timeout: Duration) {
        lock.lock()
        if cancelledEarly { lock.unlock(); continuation.resume(returning: .failed); return }
        self.continuation = continuation
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let connection = NWConnection(host: NWEndpoint.Host(host.description), port: port, using: parameters)
        self.connection = connection
        lock.unlock()

        let started = DispatchTime.now()
        func elapsed() -> Double { Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000 }
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.finish(.open(latencyMs: elapsed()))
            case .waiting(let error):
                // A refusal or a missing route can show up as "waiting" first; anything else waits for the timeout.
                if let result = LocalNetworkClassifier.result(for: error, latencyMs: elapsed()) { self?.finish(result) }
            case .failed(let error):
                self?.finish(LocalNetworkClassifier.result(for: error, latencyMs: elapsed()) ?? .failed)
            default:
                break
            }
        }
        connection.start(queue: queue)
        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        queue.asyncAfter(deadline: .now() + seconds) { [weak self] in self?.finish(.timeout) }
    }

    func cancel() {
        lock.lock()
        let began = continuation != nil
        if !began { cancelledEarly = true }
        lock.unlock()
        if began { finish(.failed) }
    }

    private func finish(_ result: ConnectResult) {
        lock.lock()
        guard !finished, let continuation else { lock.unlock(); return }
        finished = true
        let connection = connection
        self.continuation = nil
        self.connection = nil
        lock.unlock()
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        continuation.resume(returning: result)
    }
}
