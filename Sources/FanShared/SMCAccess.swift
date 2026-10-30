import Foundation

/// Read access to the SMC. Implemented by `AppleSMCReadOnlyClient` (app and helper) and by the
/// helper's `AppleSMCClient`; tests use fakes.
public protocol SMCReader: AnyObject, Sendable {
    func keyInfo(_ key: SMCKey) throws -> SMCKeyInfo
    func read(_ key: SMCKey) throws -> SMCValue
}

/// Write access to the SMC. Only the root helper has a real implementation; the app target has
/// none. Every caller goes through `FanControlCore`, which runs `FanSafetyPolicy` first.
public protocol SMCWriter: AnyObject, Sendable {
    func write(_ key: SMCKey, bytes: [UInt8]) throws
}

/// The fan keys used by this lane. `F%d` keys exist for indexes 0...9 only (one digit).
public enum FanSMCKeys {
    public static let fanCount = SMCKey("FNum")!
    /// Reported (community tools, not Apple) as the "test mode" unlock that M-series Macs need
    /// before `F%dMd` accepts manual mode. Whether the M4 Pro needs it is UNKNOWN.
    public static let unlock = SMCKey("Ftst")!
    public static let maxFanIndex = 9

    public static func actual(_ fan: Int) -> SMCKey? { key(fan, "Ac") }
    public static func minimum(_ fan: Int) -> SMCKey? { key(fan, "Mn") }
    public static func maximum(_ fan: Int) -> SMCKey? { key(fan, "Mx") }
    public static func target(_ fan: Int) -> SMCKey? { key(fan, "Tg") }
    public static func mode(_ fan: Int) -> SMCKey? { key(fan, "Md") }

    /// The only keys the helper's writer accepts: `Ftst`, `F<digit>Md`, `F<digit>Tg`. Anything else
    /// (limits, sensors, power keys) is refused before reaching the SMC.
    public static func isWritable(_ key: SMCKey) -> Bool {
        if key == unlock { return true }
        let chars = Array(key.description)
        guard chars.count == 4, chars[0] == "F", let digit = chars[1].wholeNumberValue,
              (0...maxFanIndex).contains(digit), chars[1].isASCII else { return false }
        let suffix = String(chars[2...3])
        return suffix == "Md" || suffix == "Tg"
    }

    private static func key(_ fan: Int, _ suffix: String) -> SMCKey? {
        guard (0...maxFanIndex).contains(fan) else { return nil }
        return SMCKey("F\(fan)\(suffix)")
    }
}

/// Mode values written to `F%dMd`: 0 automatic, 1 manual (forced). Reported by community tools for
/// M1-M3; any other value read back is shown as unknown and never written by this code.
public enum FanModeValue {
    public static let automatic: Double = 0
    public static let manual: Double = 1
}
