import Foundation

/// The ports a port scan may visit. Fixed list: the user picks among them, never types a range.
public struct PortPreset: Identifiable, Equatable, Sendable {
    public let port: UInt16
    public let service: String
    public var id: UInt16 { port }

    public static let all: [PortPreset] = [
        PortPreset(port: 21, service: "FTP"), PortPreset(port: 22, service: "SSH"), PortPreset(port: 23, service: "Telnet"),
        PortPreset(port: 53, service: "DNS"), PortPreset(port: 80, service: "HTTP"), PortPreset(port: 139, service: "NetBIOS"),
        PortPreset(port: 443, service: "HTTPS"), PortPreset(port: 445, service: "SMB"), PortPreset(port: 515, service: "LPD"),
        PortPreset(port: 548, service: "AFP"), PortPreset(port: 631, service: "IPP"), PortPreset(port: 1883, service: "MQTT"),
        PortPreset(port: 3389, service: "RDP"), PortPreset(port: 5900, service: "VNC"), PortPreset(port: 8000, service: "HTTP alt."),
        PortPreset(port: 8080, service: "HTTP proxy"), PortPreset(port: 8443, service: "HTTPS alt."), PortPreset(port: 9100, service: "Impression"),
    ]

    /// Checked on first use of the port scan.
    public static let defaultPorts: Set<UInt16> = [22, 80, 443, 445, 548, 631, 3389, 5900, 8080]

    public static let allPorts: Set<UInt16> = Set(all.map(\.port))

    /// Keeps only preset ports, in preset order, without duplicates: nothing outside the list can be scanned.
    public static func sanitized(_ requested: some Collection<UInt16>) -> [UInt16] {
        let wanted = Set(requested)
        return all.map(\.port).filter(wanted.contains)
    }

    public static func service(for port: UInt16) -> String? { all.first { $0.port == port }?.service }

    /// Web ports the result list can open in a browser.
    public static func browserURL(host: IPv4Address, port: UInt16) -> URL? {
        switch port {
        case 80, 8000, 8080: URL(string: "http://\(host)\(port == 80 ? "" : ":\(port)")")
        case 443, 8443: URL(string: "https://\(host)\(port == 443 ? "" : ":\(port)")")
        default: nil
        }
    }

    public static let notice = "Ne scannez que des appareils qui vous appartiennent."
}
