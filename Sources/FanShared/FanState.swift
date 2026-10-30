import Foundation

public enum FanMode: String, Codable, Sendable {
    case automatic, manual, unknown
}

/// One fan as read from the SMC. A field the SMC did not return is nil, never guessed.
public struct FanReading: Codable, Equatable, Sendable, Identifiable {
    public var index: Int
    public var actualRPM: Double?
    public var minRPM: Double?
    public var maxRPM: Double?
    public var targetRPM: Double?
    public var mode: FanMode

    public var id: Int { index }

    public init(index: Int, actualRPM: Double?, minRPM: Double?, maxRPM: Double?,
                targetRPM: Double?, mode: FanMode) {
        self.index = index
        self.actualRPM = actualRPM
        self.minRPM = minRPM
        self.maxRPM = maxRPM
        self.targetRPM = targetRPM
        self.mode = mode
    }
}

/// Snapshot the helper returns to the app.
public struct FanState: Codable, Equatable, Sendable {
    public var protocolVersion: Int
    public var fans: [FanReading]
    public var maxTemperatureCelsius: Double?
    public var manualActive: Bool

    public init(protocolVersion: Int, fans: [FanReading], maxTemperatureCelsius: Double?, manualActive: Bool) {
        self.protocolVersion = protocolVersion
        self.fans = fans
        self.maxTemperatureCelsius = maxTemperatureCelsius
        self.manualActive = manualActive
    }
}
