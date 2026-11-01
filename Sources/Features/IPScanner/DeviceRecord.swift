import Foundation

/// One device of the results list. Text fields are already cleaned (`DisplayText`) when a record is built.
public struct DeviceRecord: Identifiable, Equatable, Sendable {
    public let ip: IPv4Address
    public var hostName: String?
    public var serviceName: String?
    public var mac: MACAddress?
    public var vendor: String?
    public var latencyMs: Double?
    public var openPorts: [UInt16]
    public var isGateway: Bool
    public var isThisMac: Bool

    public var id: IPv4Address { ip }

    public init(ip: IPv4Address, hostName: String? = nil, serviceName: String? = nil, mac: MACAddress? = nil,
                vendor: String? = nil, latencyMs: Double? = nil, openPorts: [UInt16] = [],
                isGateway: Bool = false, isThisMac: Bool = false) {
        self.ip = ip
        self.hostName = hostName
        self.serviceName = serviceName
        self.mac = mac
        self.vendor = vendor
        self.latencyMs = latencyMs
        self.openPorts = openPorts
        self.isGateway = isGateway
        self.isThisMac = isThisMac
    }

    /// Reverse DNS first, then the Bonjour name; "Ce Mac" for this machine when nothing else names it.
    public var displayName: String? { hostName ?? serviceName ?? (isThisMac ? "Ce Mac" : nil) }
}

public enum ResultSort: String, CaseIterable, Identifiable, Sendable {
    case ip, name, vendor, latency
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .ip: "Adresse IP"
        case .name: "Nom"
        case .vendor: "Fabricant"
        case .latency: "Latence"
        }
    }
}

public enum ResultFilter: String, CaseIterable, Identifiable, Sendable {
    case all, named, withPorts
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .all: "Tous"
        case .named: "Avec un nom"
        case .withPorts: "Ports ouverts"
        }
    }
}

/// Sorting, filtering and searching of the results. Pure.
public enum ResultView {
    public static func apply(_ records: [DeviceRecord], sort: ResultSort, filter: ResultFilter, search: String) -> [DeviceRecord] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let kept = records.filter { record in
            switch filter {
            case .all: break
            case .named: if record.displayName == nil { return false }
            case .withPorts: if record.openPorts.isEmpty { return false }
            }
            guard !query.isEmpty else { return true }
            let haystack: [String?] = [record.ip.description, record.displayName, record.mac?.description, record.vendor,
                            record.openPorts.map(String.init).joined(separator: " ")]
            return haystack.contains { $0?.lowercased().contains(query) == true }
        }
        switch sort {
        case .ip: return kept.sorted { $0.ip < $1.ip }
        case .name: return kept.sorted { compare($0.displayName, $1.displayName) ?? ($0.ip < $1.ip) }
        case .vendor: return kept.sorted { compare($0.vendor, $1.vendor) ?? ($0.ip < $1.ip) }
        case .latency:
            return kept.sorted {
                switch ($0.latencyMs, $1.latencyMs) {
                case let (a?, b?): a == b ? $0.ip < $1.ip : a < b
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): $0.ip < $1.ip
                }
            }
        }
    }

    /// Present values sort before missing ones, case-insensitively; nil means "equal, fall back to the IP".
    private static func compare(_ a: String?, _ b: String?) -> Bool? {
        switch (a, b) {
        case let (x?, y?):
            let order = x.localizedCaseInsensitiveCompare(y)
            return order == .orderedSame ? nil : order == .orderedAscending
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return nil
        }
    }
}
