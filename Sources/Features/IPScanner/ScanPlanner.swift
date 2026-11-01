import Foundation

/// Why a scan or a port scan was not allowed. Every refusal is decided before any packet leaves.
public enum ScanRefusal: Error, Equatable, Sendable {
    /// The interface itself is not on a private or link-local range: nothing is scanned.
    case interfaceNotLocal
    /// The target is not inside the interface's own subnet.
    case outsideInterfaceSubnet
    /// More hosts than `ScanPlanner.defaultLimit`; the user must confirm first.
    case needsConfirmation(hostCount: Int)
    /// More hosts than `ScanPlanner.hardLimit`: refused even when confirmed.
    case tooLarge(hostCount: Int)
    /// A port scan aimed at an address that is not a host of a local subnet.
    case invalidHost
    case invalidRange
    case noInterface
    case featureOff
    case alreadyRunning

    public var message: String {
        switch self {
        case .interfaceNotLocal: "Ce réseau n’est pas un réseau local (adresse publique) : aucun scan n’est lancé."
        case .outsideInterfaceSubnet: "Cette plage sort du sous-réseau de l’interface : refusée."
        case .needsConfirmation(let n): "Cette plage compte \(n) adresses : confirmez pour la parcourir."
        case .tooLarge(let n): "Cette plage compte \(n) adresses : c’est trop, elle est refusée."
        case .invalidHost: "Cette adresse n’est pas un appareil de votre réseau local."
        case .invalidRange: "Plage invalide (exemple : 192.168.1.0/24)."
        case .noInterface: "Aucune interface réseau active."
        case .featureOff: "La fonction est désactivée."
        case .alreadyRunning: "Un scan est déjà en cours."
        }
    }
}

/// Decides what a scan may visit. Pure: it never touches the network.
public enum ScanPlanner {
    /// Up to a /22 (1022 hosts) a scan starts on one click.
    public static let defaultLimit = 1022
    /// A /16 (65 534 hosts) is the ceiling even with confirmation.
    public static let hardLimit = 65_534

    /// The addresses to visit. `requested` nil means the interface's whole subnet.
    /// - Refuses an interface that is not private or link-local, a range not inside the interface's subnet,
    ///   a range over `defaultLimit` unless `confirmedLarge`, and a range over `hardLimit` always.
    public static func plan(interface: IPv4Subnet, requested: IPv4Subnet? = nil,
                            confirmedLarge: Bool = false) throws -> [IPv4Address] {
        guard interface.network.isLocalScannable, interface.broadcast.isLocalScannable else { throw ScanRefusal.interfaceNotLocal }
        let target = requested ?? interface
        guard interface.contains(target) else { throw ScanRefusal.outsideInterfaceSubnet }
        let count = target.hostCount
        if count > hardLimit { throw ScanRefusal.tooLarge(hostCount: count) }
        if count > defaultLimit, !confirmedLarge { throw ScanRefusal.needsConfirmation(hostCount: count) }
        return target.hosts()
    }

    /// A port scan targets one real host of one of the active local subnets, nothing else.
    public static func validateHost(_ host: IPv4Address, in subnets: [IPv4Subnet]) throws {
        guard host.isLocalScannable, !host.isLoopback, !host.isMulticast,
              subnets.contains(where: { $0.network.isLocalScannable && $0.isHost(host) }) else {
            throw ScanRefusal.invalidHost
        }
    }
}
