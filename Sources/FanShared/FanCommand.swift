import Foundation

/// What the app asks the helper to do. Travels as JSON inside `Data` (see `FanWire`).
public enum FanCommand: Codable, Equatable, Sendable {
    /// Manual mode at `rpm` for one fan. The helper clamps and may refuse (`FanSafetyPolicy`).
    case setTarget(fan: Int, rpm: Double)
    /// Automatic mode for one fan.
    case automatic(fan: Int)
    /// Automatic mode for every fan. Always allowed, never rate-limited.
    case allAutomatic
}

/// The helper's answer to a `FanCommand`.
public struct FanCommandResult: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case applied, automatic, forcedAutomatic, rejected, failed
    }

    public var status: Status
    public var fan: Int?
    public var appliedRPM: Double?
    /// Machine code: unknownFan, invalidLimits, invalidRequest, rateLimited, thermal, writeFailed,
    /// notConfirmed, restorePending, unsupportedKey, protocolVersion (manual request before a
    /// matching `hello`, set by the helper's connection, not by `FanControlCore`).
    public var reason: String?
    public var retryAfter: Double?

    public init(status: Status, fan: Int? = nil, appliedRPM: Double? = nil,
                reason: String? = nil, retryAfter: Double? = nil) {
        self.status = status
        self.fan = fan
        self.appliedRPM = appliedRPM
        self.reason = reason
        self.retryAfter = retryAfter
    }
}

/// Why the helper went back to automatic mode.
public enum RestoreReason: String, Codable, Sendable {
    case clientRequest, watchdog, thermal, disconnected, shutdown, startup, writeFailed
}
