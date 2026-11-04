import AppKit
import Foundation
import IslandKit
import Network
import ShellKit

/// "Adresse IP" status chip: the local IPv4 of the primary interface, "VPN actif" when a tunnel is up.
///
/// Nothing runs before `start()`, and then only once (plus once per change of network path, reported by
/// `NWPathMonitor`): no timer. The public address is NEVER fetched by itself. The "Afficher l’IP publique" action
/// performs one request (the same fetcher, URL and validation as the scanner's opt-in button), shows the answer as
/// the secondary text for `publicIPDuration`, then forgets it. `stop()` forgets it at once.
@MainActor
public final class IPChipSource: StatusChipSource {
    /// How long a public address stays on the chip.
    public nonisolated static let publicIPDuration: Duration = .seconds(60)

    public let kind: StatusChipKind = .ip
    public private(set) var reading: StatusChipReading?
    public var onChange: (@MainActor () -> Void)?

    private enum PublicState: Equatable {
        case fetching
        case value(String)
        case failed
    }

    private let interfaces: any InterfaceProviding
    private let tunnelReadings: @Sendable () -> [InterfaceReading]
    private let fetcher: any PublicIPFetching
    private let copy: @MainActor (String) -> Void
    private let openScanner: (@MainActor () -> Void)?
    /// Asked each time the chip is rebuilt: the scanner tab only exists while its feature is switched on.
    private let scannerAvailable: @MainActor () -> Bool
    private let sleep: @Sendable (Duration) async throws -> Void
    private let watchPath: Bool
    private let pathQueue = DispatchQueue(label: "be.roldy.macisland.chip-ip-path", qos: .utility)

    private var isRunning = false
    private var monitor: NWPathMonitor?
    private var localAddress: String?
    private var vpn = false
    private var publicState: PublicState?
    private var fetchTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?

    public init(interfaces: any InterfaceProviding = SystemInterfaceProvider(),
                tunnelReadings: @escaping @Sendable () -> [InterfaceReading] = { TunnelReadings.current() },
                fetcher: any PublicIPFetching = URLSessionPublicIPFetcher(),
                copy: @escaping @MainActor (String) -> Void = { text in
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                },
                openScanner: (@MainActor () -> Void)? = nil,
                scannerAvailable: @escaping @MainActor () -> Bool = { true },
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0, tolerance: .seconds(1)) },
                watchPath: Bool = true) {
        self.interfaces = interfaces
        self.tunnelReadings = tunnelReadings
        self.fetcher = fetcher
        self.copy = copy
        self.openScanner = openScanner
        self.scannerAvailable = scannerAvailable
        self.sleep = sleep
        self.watchPath = watchPath
    }

    // MARK: - Reading

    /// The chip for one state. Pure: the tests drive it directly.
    static func reading(local: String, vpn: Bool, publicIP: String?, failed: Bool = false, fetching: Bool = false,
                        actions: [StatusChipAction] = []) -> StatusChipReading {
        var parts: [String] = []
        if let publicIP { parts.append("Publique \(publicIP)") } else if fetching { parts.append("Recherche…") } else if failed {
            parts.append("IP publique indisponible")
        }
        if vpn { parts.append("VPN actif") }
        return StatusChipReading(kind: .ip, primary: local, secondary: parts.isEmpty ? nil : parts.joined(separator: " · "),
                                 level: .normal, actions: actions)
    }

    private func rebuild() {
        guard isRunning else { return }
        var next: StatusChipReading?
        if let local = localAddress {
            var actions = [StatusChipAction(id: "copy-local", title: "Copier l’adresse locale", systemImage: "doc.on.doc",
                                            handler: { [weak self] in self?.copyLocal() })]
            actions.append(StatusChipAction(id: "public-ip", title: "Afficher l’IP publique", systemImage: "globe",
                                            handler: { [weak self] in self?.showPublicIP() }))
            if let openScanner, scannerAvailable() {
                actions.append(StatusChipAction(id: "scanner", title: "Ouvrir le scanner IP",
                                                systemImage: "dot.radiowaves.left.and.right", handler: openScanner))
            }
            var shown: String?
            if case .value(let ip) = publicState { shown = ip }
            next = Self.reading(local: local, vpn: vpn, publicIP: shown, failed: publicState == .failed,
                                fetching: publicState == .fetching, actions: actions)
        }
        guard next != reading else { return }
        reading = next
        onChange?()
    }

    // MARK: - Lifecycle

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        refresh()
        guard watchPath else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        monitor.start(queue: pathQueue)
        self.monitor = monitor
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        monitor?.cancel()
        monitor = nil
        fetchTask?.cancel()
        fetchTask = nil
        expiryTask?.cancel()
        expiryTask = nil
        publicState = nil
        localAddress = nil
        vpn = false
        reading = nil
    }

    /// Re-reads the primary address and the tunnel state (on start and on each path change).
    func refresh() {
        guard isRunning else { return }
        let address = interfaces.interfaces().first?.address.description
        let tunnel = SamplingMath.vpnActive(tunnelReadings())
        if address != localAddress || tunnel != vpn {
            // The network changed: a public IP shown (or being fetched) belongs to the old path. Forget it and drop
            // the answer of a request still in flight (it checks `isCancelled`).
            fetchTask?.cancel()
            fetchTask = nil
            expiryTask?.cancel()
            expiryTask = nil
            publicState = nil
        }
        localAddress = address
        vpn = tunnel
        rebuild()
    }

    // MARK: - Actions (each one is a click)

    private func copyLocal() {
        guard let localAddress else { return }
        copy(localAddress)  // the user's own private address, not a secret
    }

    /// ONE request, on the click only. A second click while one is in flight does nothing.
    @discardableResult
    func showPublicIP() -> Task<Void, Never>? {
        guard isRunning, publicState != .fetching else { return fetchTask }
        expiryTask?.cancel()
        expiryTask = nil
        publicState = .fetching
        rebuild()
        let fetcher = self.fetcher
        let task = Task { [weak self] in
            let answer = try? await fetcher.fetch(from: PublicIPLookup.url)
            guard let self, !Task.isCancelled, self.isRunning else { return }
            self.publicState = answer.flatMap(PublicIPLookup.validated).map(PublicState.value) ?? .failed
            self.fetchTask = nil
            self.rebuild()
            self.scheduleForgetting()
        }
        fetchTask = task
        return task
    }

    private func scheduleForgetting() {
        let sleep = self.sleep
        expiryTask = Task { [weak self] in
            try? await sleep(Self.publicIPDuration)
            guard let self, !Task.isCancelled, self.isRunning else { return }
            self.publicState = nil
            self.expiryTask = nil
            self.rebuild()
        }
    }

    /// Test seam: the request in flight, if any.
    var pendingFetch: Task<Void, Never>? { fetchTask }

    /// Test seam: waits for the pending forgetting timer.
    func waitForForgetting() async { await expiryTask?.value }
}
