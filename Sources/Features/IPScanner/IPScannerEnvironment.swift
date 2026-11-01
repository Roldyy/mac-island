import AppKit
import Foundation

/// Everything the model reaches outside itself. The live value is the only place that touches the network, the
/// pasteboard, the disk or the workspace; a test builds its own with fakes.
public struct IPScannerEnvironment: Sendable {
    public var interfaces: any InterfaceProviding
    public var services: ScanServices
    public var ports: any PortProbing
    public var publicIP: any PublicIPFetching
    public var localNetwork: any LocalNetworkChecking
    public var copyToPasteboard: @MainActor @Sendable (String) -> Void
    /// Writes the CSV where the user can find it and returns the file name shown in the confirmation.
    public var saveCSV: @MainActor @Sendable (String) throws -> String
    public var open: @MainActor @Sendable (URL) -> Void

    public init(interfaces: any InterfaceProviding, services: ScanServices, ports: any PortProbing,
                publicIP: any PublicIPFetching, localNetwork: any LocalNetworkChecking,
                copyToPasteboard: @escaping @MainActor @Sendable (String) -> Void,
                saveCSV: @escaping @MainActor @Sendable (String) throws -> String,
                open: @escaping @MainActor @Sendable (URL) -> Void) {
        self.interfaces = interfaces
        self.services = services
        self.ports = ports
        self.publicIP = publicIP
        self.localNetwork = localNetwork
        self.copyToPasteboard = copyToPasteboard
        self.saveCSV = saveCSV
        self.open = open
    }

    public static let live = IPScannerEnvironment(
        interfaces: SystemInterfaceProvider(), services: .live, ports: TCPPortProber(),
        publicIP: URLSessionPublicIPFetcher(), localNetwork: SystemLocalNetworkChecker(),
        copyToPasteboard: { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        },
        saveCSV: { csv in
            let directory = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let stamp = DateFormatter()
            stamp.locale = Locale(identifier: "en_US_POSIX")
            stamp.dateFormat = "yyyyMMdd-HHmmss"
            let name = "scan-ip-\(stamp.string(from: Date())).csv"
            let url = directory.appendingPathComponent(name)
            try Data(csv.utf8).write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return name
        },
        open: { NSWorkspace.shared.open($0) })
}

/// The Local Network pane of System Settings (opening it never asks for anything).
public enum LocalNetworkPane {
    public static let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")!
}
