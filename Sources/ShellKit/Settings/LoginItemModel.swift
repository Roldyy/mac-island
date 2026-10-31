import Foundation
import Observation
import ServiceManagement

/// What the system says about the login item.
public enum LoginItemStatus: Equatable, Sendable {
    case enabled, disabled, requiresApproval, unavailable

    init(_ status: SMAppService.Status) {
        switch status {
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notRegistered: self = .disabled
        case .notFound: self = .unavailable
        @unknown default: self = .unavailable
        }
    }

    /// One line shown under the switch.
    public var sentence: String {
        switch self {
        case .enabled: "L’app s’ouvre à chaque démarrage du Mac."
        case .disabled: "L’app ne s’ouvre pas toute seule."
        case .requiresApproval: "Autorisez Mac Island dans Réglages Système, Éléments de connexion."
        case .unavailable: "L’app doit être installée : un binaire lancé du terminal ne peut pas s’inscrire."
        }
    }
}

/// The part of `SMAppService` the model needs, so tests can stand in for it.
@MainActor
public protocol LoginItemService {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
    /// The status read without blocking the main thread. Defaults to the synchronous read.
    func currentStatus() async -> LoginItemStatus
}

extension LoginItemService {
    public func currentStatus() async -> LoginItemStatus { status }
}

@MainActor
public struct SystemLoginItemService: LoginItemService {
    public init() {}
    public var status: LoginItemStatus { LoginItemStatus(SMAppService.mainApp.status) }
    /// `SMAppService.status` talks to a system daemon: read it on a background thread.
    public func currentStatus() async -> LoginItemStatus {
        await Task.detached(priority: .userInitiated) { LoginItemStatus(SMAppService.mainApp.status) }.value
    }
    public func register() throws { try SMAppService.mainApp.register() }
    public func unregister() throws { try SMAppService.mainApp.unregister() }
    public func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// "Ouvrir à l’ouverture de session": the real state comes from the system, the wish is kept in
/// the migrated key `launchAtLoginWanted`.
@MainActor @Observable
public final class LoginItemModel {
    public static let wantedKey = "launchAtLoginWanted"

    public private(set) var status: LoginItemStatus
    public private(set) var errorMessage: String?

    @ObservationIgnored private let service: any LoginItemService
    @ObservationIgnored private let defaults: UserDefaults

    public init(service: (any LoginItemService)? = nil, defaults: UserDefaults) {
        let service = service ?? SystemLoginItemService()
        self.service = service
        self.defaults = defaults
        status = service.status
    }

    /// The switch is on when the item runs or waits for the user's approval.
    public var isOn: Bool { status == .enabled || status == .requiresApproval }

    public func refresh() { status = service.status }

    /// Shows the last known status at once and updates it when the system answers.
    public func refreshInBackground() async {
        let fresh = await service.currentStatus()
        if fresh != status { status = fresh }
    }

    public func set(_ on: Bool) {
        errorMessage = nil
        do {
            if on { try service.register() } else { try service.unregister() }
            defaults.set(on, forKey: Self.wantedKey)
        } catch {
            errorMessage = "Le système a refusé : \(error.localizedDescription)"
        }
        refresh()
    }

    public func openSystemSettings() { service.openSystemSettings() }
}
