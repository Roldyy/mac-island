import Foundation
import Network

/// Bonjour names through `NWBrowser`. It browses a fixed list of common service types for a few seconds, then learns each
/// service's IPv4 address by opening the connection the system would open to use it (the path's remote endpoint) and
/// closing it at once. Live code: never called from a test. Names are untrusted and go through `DisplayText`.
public final class BonjourDiscovery: ServiceDiscovering, @unchecked Sendable {
    public static let serviceTypes = [
        "_workstation._tcp", "_device-info._tcp", "_airplay._tcp", "_raop._tcp", "_companion-link._tcp", "_googlecast._tcp",
        "_hap._tcp", "_http._tcp", "_ipp._tcp", "_printer._tcp", "_smb._tcp", "_afpovertcp._tcp", "_ssh._tcp",
    ]

    public init() {}

    public func discover(within duration: Duration, limit: Int) async -> ServiceDiscovery {
        let collector = Collector()
        let queue = DispatchQueue(label: "be.roldy.macisland.ipscanner.bonjour", qos: .utility)
        let browsers = Self.serviceTypes.map { NWBrowser(for: .bonjour(type: $0, domain: nil), using: .tcp) }
        for browser in browsers {
            browser.stateUpdateHandler = { state in
                switch state {
                case .waiting(let error), .failed(let error):
                    if LocalNetworkClassifier.isPolicyDenial(error) { collector.markDenied() }
                default: break
                }
            }
            browser.browseResultsChangedHandler = { results, _ in collector.add(results) }
            browser.start(queue: queue)
        }
        try? await Task.sleep(for: duration)
        browsers.forEach { $0.cancel() }
        guard !Task.isCancelled else { return ServiceDiscovery(policyDenied: collector.denied) }

        var names: [IPv4Address: String] = [:]
        let services = Array(collector.services.prefix(max(0, limit)))
        var index = 0
        while index < services.count, !Task.isCancelled {
            let batch = services[index..<min(index + 8, services.count)]
            index += 8
            await withTaskGroup(of: (IPv4Address, String)?.self) { group in
                for service in batch { group.addTask { await Self.resolve(service) } }
                for await pair in group {
                    if let (ip, name) = pair, names[ip] == nil { names[ip] = name }
                }
            }
        }
        return ServiceDiscovery(names: names, policyDenied: collector.denied)
    }

    private struct Service: Sendable {
        let name: String
        let endpoint: NWEndpoint
    }

    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [String: Service] = [:]
        private var isDenied = false

        var services: [Service] { lock.lock(); defer { lock.unlock() }; return Array(seen.values) }
        var denied: Bool { lock.lock(); defer { lock.unlock() }; return isDenied }
        func markDenied() { lock.lock(); isDenied = true; lock.unlock() }

        func add(_ results: Set<NWBrowser.Result>) {
            lock.lock(); defer { lock.unlock() }
            for result in results {
                guard case let .service(name, type, domain, _) = result.endpoint, seen.count < 512,
                      let clean = DisplayText.clean(name) else { continue }
                seen["\(name)|\(type)|\(domain)"] = Service(name: clean, endpoint: result.endpoint)
            }
        }
    }

    private static func resolve(_ service: Service) async -> (IPv4Address, String)? {
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let connection = NWConnection(to: service.endpoint, using: parameters)
        let address: IPv4Address? = await withCheckedContinuation { (continuation: CheckedContinuation<IPv4Address?, Never>) in
            let once = OnceResume(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case let .hostPort(host, _)? = connection.currentPath?.remoteEndpoint, case .ipv4(let v4) = host {
                        let raw = v4.rawValue
                        once.resume(raw.count == 4 ? IPv4Address(raw.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }) : nil)
                    } else {
                        once.resume(nil)
                    }
                case .failed, .cancelled:
                    once.resume(nil)
                default: break
                }
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.5) { once.resume(nil) }
        }
        connection.stateUpdateHandler = nil
        connection.cancel()
        guard let address, address.isLocalScannable else { return nil }
        return (address, service.name)
    }
}
