import FanShared
import Foundation
import ServiceManagement

/// `SMAppService.Status` of the helper daemon, as the UI shows it.
enum HelperInstallStatus: Equatable, Sendable {
    /// Never registered (or unregistered): an "Installer le helper" button registers it.
    case notRegistered
    /// Registered, waiting for the user in System Settings > General > Login Items.
    case requiresApproval
    /// Approved: launchd starts the helper when the app connects.
    case enabled
    /// The plist is not in `Contents/Library/LaunchDaemons` (unbundled build, `swift run`).
    case notFound

    init(_ status: SMAppService.Status) {
        switch status {
        case .notRegistered: self = .notRegistered
        case .requiresApproval: self = .requiresApproval
        case .enabled: self = .enabled
        case .notFound: self = .notFound
        @unknown default: self = .notFound
        }
    }
}

/// Registration of the helper daemon. Only ever called from an explicit click, never at launch.
protocol FanHelperInstalling: AnyObject {
    var status: HelperInstallStatus { get }
    func register() throws
    func openLoginItems()
}

/// `SMAppService.daemon(plistName:)` (macOS 13+). The first `register()` leaves the daemon in
/// `requiresApproval` until an admin enables it in System Settings > Login Items.
/// COMPILE-ONLY in this lane: needs the signed, bundled app with the plist shipped.
final class SMAppServiceInstaller: FanHelperInstalling {
    private let service = SMAppService.daemon(plistName: FanHelperContract.daemonPlistName)

    var status: HelperInstallStatus { HelperInstallStatus(service.status) }

    func register() throws { try service.register() }

    func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}
