import Foundation

/// Everything the app and the root helper must agree on. Changing a value here is a protocol change.
public enum FanHelperContract {
    /// launchd label and Mach service name (the daemon plist's `Label` and `MachServices` key).
    public static let machServiceName = "be.roldy.macisland.fanhelper"
    /// Code-signing identifier the helper binary must carry (`codesign -i`).
    public static let helperIdentifier = "be.roldy.macisland.fanhelper"
    /// Bundle identifier of the app, the only client the helper accepts.
    public static let appIdentifier = "be.roldy.macisland"
    public static let teamID = "U3TUL63HHK"
    /// Plist in `Mac Island.app/Contents/Library/LaunchDaemons/`, passed to `SMAppService.daemon(plistName:)`.
    public static let daemonPlistName = "be.roldy.macisland.fanhelper.plist"
    /// Bump on any change to `FanHelperXPC`, `FanCommand` or `FanState`.
    public static let protocolVersion = 1

    /// What the helper requires of a connecting client (`NSXPCListener.setConnectionCodeSigningRequirement`).
    public static let clientRequirement = developerIDRequirement(identifier: appIdentifier)
    /// What the app requires of the helper it talks to (`NSXPCConnection.setCodeSigningRequirement`).
    public static let helperRequirement = developerIDRequirement(identifier: helperIdentifier)

    /// One requirement for both ends, only the identifier differs: Apple-anchored, team
    /// U3TUL63HHK, and Developer ID Application only, through the Developer ID CA intermediate
    /// (`certificate 1[field.1.2.840.113635.100.6.2.6]`) and the Developer ID Application leaf
    /// (`certificate leaf[field.1.2.840.113635.100.6.1.13]`). Without the two OID clauses an
    /// Apple Development certificate of the same team would also pass.
    ///
    /// Consequence, intended: a dev build (`swift run`, Apple Development or ad-hoc signed) cannot
    /// drive the helper. The helper refuses the app, the app refuses the helper, manual control
    /// stays off; read-only monitoring does not need the helper and keeps working.
    private static func developerIDRequirement(identifier: String) -> String {
        #"anchor apple generic and certificate leaf[subject.OU] = "\#(teamID)" and identifier "\#(identifier)""#
            + " and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
    }

    /// The app sends a heartbeat this often while manual control is active.
    public static let heartbeatInterval: TimeInterval = 2
    /// The helper restores automatic mode when no heartbeat arrived for this long (4 missed beats).
    public static let watchdogTimeout: TimeInterval = 8
    /// The helper checks the watchdog and the temperature this often.
    public static let tickInterval: TimeInterval = 1
    /// Upper bound for any JSON payload crossing the XPC boundary.
    public static let maxPayloadBytes = 16 * 1024
}
