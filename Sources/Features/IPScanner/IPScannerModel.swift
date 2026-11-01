import Foundation
import Observation

/// State and actions of the IP scanner, shared by the island tab and the Settings page.
///
/// Nothing here runs by itself: `start()` only marks the feature as allowed, and every network action (the local
/// network check, a scan, a port scan, the public IP lookup) starts from a method a button calls. `stop()` (kill switch,
/// switch off, safe mode) cancels everything and forgets the results.
@MainActor @Observable
public final class IPScannerModel {
    public enum ScanState: Equatable {
        case idle
        case scanning(ScanProgress)
        case finished(devices: Int, seconds: Double)
        case cancelled
        case failed(String)

        public var isScanning: Bool { if case .scanning = self { true } else { false } }
    }

    public enum PortScanState: Equatable {
        case idle
        case scanning(host: IPv4Address, done: Int, total: Int)
        case finished(host: IPv4Address, open: [UInt16])
        case failed(String)

        public var isScanning: Bool { if case .scanning = self { true } else { false } }
    }

    public enum PublicIPState: Equatable {
        case notFetched, fetching, value(String), failed
    }

    public let settings: IPScannerSettings
    @ObservationIgnored private let environment: IPScannerEnvironment
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var portTask: Task<Void, Never>?
    @ObservationIgnored private var accessTask: Task<Void, Never>?
    @ObservationIgnored private var publicIPTask: Task<Void, Never>?

    public private(set) var isActive = false
    public private(set) var interfaces: [LocalInterface] = []
    public var selectedInterfaceID: String?
    /// Optional narrower range (CIDR) inside the interface's subnet. Empty means the whole subnet.
    public var rangeText = ""
    public private(set) var scanState: ScanState = .idle
    public private(set) var devices: [DeviceRecord] = []
    public var search = ""
    public var sort: ResultSort = .ip
    public var filter: ResultFilter = .all
    public var selectedHost: IPv4Address?
    public private(set) var portScanState: PortScanState = .idle
    public private(set) var publicIP: PublicIPState = .notFetched
    public private(set) var localNetwork: LocalNetworkState = .unknown
    public private(set) var checkingLocalNetwork = false
    /// A range over the default limit waits here for the user's confirmation.
    public private(set) var pendingConfirmation: Int?
    /// The one-line feedback under the controls (copied, saved, refused...).
    public private(set) var notice: String?

    public init(environment: IPScannerEnvironment = .live, settings: IPScannerSettings) {
        self.environment = environment
        self.settings = settings
    }

    // MARK: - Lifecycle (the registry's door)

    public func start() { isActive = true }

    /// Cancels every task and drops the results: nothing outlives the switch.
    public func stop() {
        isActive = false
        scanTask?.cancel()
        portTask?.cancel()
        accessTask?.cancel()
        publicIPTask?.cancel()
        scanTask = nil
        portTask = nil
        accessTask = nil
        publicIPTask = nil
        scanState = .idle
        portScanState = .idle
        devices = []
        selectedHost = nil
        publicIP = .notFetched
        checkingLocalNetwork = false
        pendingConfirmation = nil
        notice = nil
        search = ""
    }

    // MARK: - Interfaces (read only, no packet)

    public func refreshInterfaces() {
        guard isActive else { return }
        interfaces = environment.interfaces.interfaces()
        if selectedInterface == nil { selectedInterfaceID = (interfaces.first(where: \.isScannable) ?? interfaces.first)?.id }
    }

    public var selectedInterface: LocalInterface? { interfaces.first { $0.id == selectedInterfaceID } }

    public var visibleDevices: [DeviceRecord] { ResultView.apply(devices, sort: sort, filter: filter, search: search) }

    // MARK: - Scan

    /// The addresses the current form would scan, or the reason it would not.
    func plannedTargets(confirmedLarge: Bool) throws -> (ScanContext, [IPv4Address]) {
        guard isActive else { throw ScanRefusal.featureOff }
        guard let interface = selectedInterface else { throw ScanRefusal.noInterface }
        var requested: IPv4Subnet?
        let text = rangeText.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty {
            guard let parsed = IPv4Subnet(cidr: text) else { throw ScanRefusal.invalidRange }
            requested = parsed
        }
        let targets = try ScanPlanner.plan(interface: interface.subnet, requested: requested, confirmedLarge: confirmedLarge)
        return (ScanContext(interface), targets)
    }

    public func startScan(confirmedLarge: Bool = false) {
        guard !scanState.isScanning else { return report(ScanRefusal.alreadyRunning) }
        pendingConfirmation = nil
        let planned: (ScanContext, [IPv4Address])
        do {
            planned = try plannedTargets(confirmedLarge: confirmedLarge)
        } catch ScanRefusal.needsConfirmation(let count) {
            pendingConfirmation = count
            notice = ScanRefusal.needsConfirmation(hostCount: count).message
            return
        } catch {
            return report(error)
        }
        let (context, targets) = planned
        notice = nil
        devices = []
        selectedHost = nil
        portScanState = .idle
        let configuration = settings.scanConfiguration
        let services = environment.services
        let started = ContinuousClock.now
        scanState = .scanning(ScanProgress(done: 0, total: targets.count, found: 0, phase: .probing))
        let onProgress: @Sendable (ScanProgress) -> Void = { [weak self] progress in
            Task { @MainActor in self?.apply(progress) }
        }
        scanTask = Task { [weak self] in
            do {
                let found = try await ScanEngine.run(targets: targets, context: context, configuration: configuration,
                                                     services: services, progress: onProgress)
                self?.finishScan(found, since: started)
            } catch is CancellationError {
                // After stop() (switch off, kill switch) the model is already back to idle: a late cancellation changes nothing.
                if self?.isActive == true { self?.scanState = .cancelled }
            } catch {
                if self?.isActive == true { self?.report(error) }
            }
            self?.scanTask = nil
        }
    }

    public func confirmPendingScan() { startScan(confirmedLarge: true) }

    public func dismissConfirmation() { pendingConfirmation = nil }

    public func cancelScan() {
        scanTask?.cancel()
    }

    private func apply(_ progress: ScanProgress) {
        // Progress hops through unstructured tasks: a late one must never move the bar backwards or revive a finished scan.
        guard case .scanning(let current) = scanState else { return }
        func rank(_ phase: ScanProgress.Phase) -> Int { phase == .probing ? 0 : (phase == .readingTable ? 1 : 2) }
        if (rank(progress.phase), progress.done) >= (rank(current.phase), current.done) { scanState = .scanning(progress) }
    }

    private func finishScan(_ found: [DeviceRecord], since start: ContinuousClock.Instant) {
        guard isActive else { return }
        devices = found
        let elapsed = start.duration(to: .now)
        scanState = .finished(devices: found.count, seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
    }

    private func report(_ error: Error) {
        let message = (error as? ScanRefusal)?.message ?? "Le scan a échoué."
        notice = message
        if !scanState.isScanning { scanState = .failed(message) }
    }

    // MARK: - Port scan (one host, presets only, on click)

    public func scanPorts(of host: IPv4Address) {
        guard isActive else { return report(ScanRefusal.featureOff) }
        guard !portScanState.isScanning else { return }
        let subnets = interfaces.map(\.subnet)
        do { try ScanPlanner.validateHost(host, in: subnets) } catch { portScanState = .failed(ScanRefusal.invalidHost.message); return }
        let ports = PortPreset.sanitized(settings.ports)
        guard !ports.isEmpty else { portScanState = .failed("Choisissez au moins un port dans les Réglages."); return }
        let prober = environment.ports
        let configuration = PortScanConfiguration(timeout: .milliseconds(settings.timeoutMs))
        portScanState = .scanning(host: host, done: 0, total: ports.count)
        let onProgress: @Sendable (Int, Int) -> Void = { [weak self] done, total in
            Task { @MainActor in
                if case .scanning = self?.portScanState { self?.portScanState = .scanning(host: host, done: done, total: total) }
            }
        }
        portTask = Task { [weak self] in
            do {
                let open = try await PortScanEngine.run(host: host, ports: ports, subnets: subnets, configuration: configuration,
                                                        prober: prober, progress: onProgress)
                self?.finishPortScan(host: host, open: open)
            } catch is CancellationError {
                self?.portScanState = .idle
            } catch {
                if self?.isActive == true { self?.portScanState = .failed((error as? ScanRefusal)?.message ?? "Le scan de ports a échoué.") }
            }
            self?.portTask = nil
        }
    }

    public func cancelPortScan() { portTask?.cancel() }

    private func finishPortScan(host: IPv4Address, open: [UInt16]) {
        guard isActive else { return }
        if let index = devices.firstIndex(where: { $0.ip == host }) { devices[index].openPorts = open }
        portScanState = .finished(host: host, open: open)
    }

    // MARK: - Local network permission (the "Autoriser" click)

    /// The first local connection of the session, made on click only: this is what makes macOS ask.
    public func requestLocalNetworkAccess() {
        guard isActive, !checkingLocalNetwork else { return }
        guard let gateway = selectedInterface?.gateway else {
            notice = "Aucune passerelle connue : lancez un scan, macOS demandera l’accès à ce moment."
            return
        }
        checkingLocalNetwork = true
        let checker = environment.localNetwork
        accessTask = Task { [weak self] in
            let state = await checker.check(target: gateway)
            guard let self, !Task.isCancelled, self.isActive else { return }
            self.localNetwork = state
            self.checkingLocalNetwork = false
            self.accessTask = nil
        }
    }

    public func openLocalNetworkPane() { environment.open(LocalNetworkPane.url) }

    // MARK: - Public IP (opt in, one request)

    public func fetchPublicIP() {
        guard isActive, publicIP != .fetching else { return }
        publicIP = .fetching
        let fetcher = environment.publicIP
        publicIPTask = Task { [weak self] in
            let answer = try? await fetcher.fetch(from: PublicIPLookup.url)
            guard let self, !Task.isCancelled, self.isActive else { return }
            self.publicIP = answer.flatMap(PublicIPLookup.validated).map(PublicIPState.value) ?? .failed
            self.publicIPTask = nil
        }
    }

    // MARK: - Results actions (each one is a click)

    public func copyIP(_ record: DeviceRecord) {
        environment.copyToPasteboard(record.ip.description)
        notice = "Adresse IP copiée."
    }

    public func copyMAC(_ record: DeviceRecord) {
        guard let mac = record.mac else { return }
        environment.copyToPasteboard(mac.description)
        notice = "Adresse MAC copiée."
    }

    public func copyCSV() {
        guard !devices.isEmpty else { return }
        environment.copyToPasteboard(CSVExport.csv(visibleDevices))
        notice = "CSV copié dans le presse-papiers."
    }

    public func saveCSV() {
        guard !devices.isEmpty else { return }
        do {
            let name = try environment.saveCSV(CSVExport.csv(visibleDevices))
            notice = "Enregistré dans Téléchargements : \(name)"
        } catch {
            notice = "Impossible d’enregistrer le fichier."
        }
    }

    public func openInBrowser(_ record: DeviceRecord, port: UInt16) {
        guard record.openPorts.contains(port), let url = PortPreset.browserURL(host: record.ip, port: port) else { return }
        environment.open(url)
    }
}
