import Foundation

/// What the helper installation looks like, in plain terms the ported fan policy can read. It mirrors
/// `HelperInstallStatus` without exposing it.
public enum FanDriverAccess: Equatable, Sendable {
    /// Never registered: only an explicit click may register it.
    case notRegistered
    /// Registered, waiting for the person in System Settings > General > Login Items.
    case requiresApproval
    /// Approved: launchd runs the helper.
    case enabled
    /// Not in this build (unbundled run): manual control cannot exist.
    case notFound
}

/// One fan as the SMC reports it, read in user space (no helper needed). A value the SMC did not return is nil.
public struct FanDriverFan: Equatable, Sendable {
    public var index: Int
    public var actualRPM: Double?
    public var minRPM: Double?
    public var maxRPM: Double?
    public var targetRPM: Double?
    /// True when the fan is in manual mode right now (ours or somebody else's).
    public var isManual: Bool

    public init(index: Int, actualRPM: Double?, minRPM: Double?, maxRPM: Double?, targetRPM: Double?, isManual: Bool) {
        self.index = index
        self.actualRPM = actualRPM
        self.minRPM = minRPM
        self.maxRPM = maxRPM
        self.targetRPM = targetRPM
        self.isManual = isManual
    }
}

/// What a command to the helper came to.
public enum FanDriverOutcome: Equatable, Sendable {
    /// Manual mode, this fan, this speed (already clamped by the helper).
    case applied(fan: Int, rpm: Double)
    /// Automatic mode (the answer to a return-to-automatic).
    case automatic
    /// The helper refused manual mode and went automatic by itself (it is too hot).
    case forcedAutomatic
    /// Refused, nothing changed. `reason` is the helper's machine code (`rateLimited`, `invalidLimits`...).
    case rejected(reason: String?)
    /// The SMC write failed; the helper put the fans back to automatic (or keeps retrying to).
    case failed(reason: String?)
    /// No answer from the helper: not approved, not running, or the call timed out.
    case unreachable
}

/// The one door the ported fan policy uses to reach Mac Island's root helper. The XPC contract (`FanHelperContract`)
/// stays what it is: this protocol sits above it and is implemented by the Fans model, so the ported curves,
/// presets and safety limits drive the very same client, heartbeat and watchdog as the Ventilos tab.
@MainActor
public protocol FanDriving: AnyObject {
    var access: FanDriverAccess { get }
    /// True once the helper answered the protocol handshake and the connection is up.
    var isReachable: Bool { get }
    /// True while the helper holds the fans in manual mode for this app.
    var isManualActive: Bool { get }
    /// Called when manual mode ended for a reason that is not this app's own command: the helper's thermal
    /// override or watchdog, a refused heartbeat, a dropped connection. The argument is a French line.
    var onManualEnded: (@MainActor (String?) -> Void)? { get set }

    /// Re-reads the installation status (an approval given in System Settings meanwhile).
    func refreshAccess()
    /// Connects when the helper is already approved. Never registers it.
    func connectIfApproved() async
    /// Registers the helper daemon. Only ever called from an explicit click.
    func installHelper()
    func openApprovalSettings()
    /// Reads every fan from the SMC (read-only). Nil when the SMC cannot be read.
    func readFans() async -> [FanDriverFan]?
    func setTarget(fan: Int, rpm: Double) async -> FanDriverOutcome
    func returnAllToAutomatic() async -> FanDriverOutcome
    /// Automatic for every fan, callable at quit: waits at most half a second, opens no connection.
    func returnAllToAutomaticNow()
}
