import Foundation

/// Manufacturer limits of one fan, as read from `F%dMn` / `F%dMx`.
public struct FanLimits: Codable, Equatable, Sendable {
    public var minRPM: Double
    public var maxRPM: Double

    public init(minRPM: Double, maxRPM: Double) {
        self.minRPM = minRPM
        self.maxRPM = maxRPM
    }
}

/// `ProcessInfo.ThermalState`, mirrored so the policy stays pure and Codable.
public enum ThermalPressure: Int, Codable, Sendable {
    case nominal, fair, serious, critical

    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .critical
        }
    }
}

public struct ThermalSnapshot: Equatable, Sendable {
    /// Hottest plausible sensor reading, nil when none could be read.
    public var maxCelsius: Double?
    public var pressure: ThermalPressure

    public init(maxCelsius: Double?, pressure: ThermalPressure) {
        self.maxCelsius = maxCelsius
        self.pressure = pressure
    }
}

public enum FanRejection: String, Error, Codable, Sendable {
    case unknownFan, invalidLimits, invalidRequest, rateLimited
}

public enum FanDecision: Equatable, Sendable {
    case apply(fan: Int, rpm: Double)
    case forceAutomatic
    case reject(FanRejection, retryAfter: TimeInterval?)
}

/// Pure safety rules, run by the app (slider range) and again by the helper before any write.
public struct FanSafetyPolicy: Equatable, Sendable {
    /// Above this hottest-sensor reading, manual mode is refused and automatic is forced.
    public var thermalLimitCelsius: Double
    /// Minimum time between two applied changes of the same fan.
    public var minChangeInterval: TimeInterval
    /// A manufacturer maximum above this is treated as a bad SMC read.
    public var maxPlausibleRPM: Double
    /// A temperature outside this range is treated as no reading (fail closed).
    public var plausibleCelsius: ClosedRange<Double>

    public init(thermalLimitCelsius: Double = 95, minChangeInterval: TimeInterval = 1,
                maxPlausibleRPM: Double = 12_000, plausibleCelsius: ClosedRange<Double> = 1...130) {
        self.thermalLimitCelsius = thermalLimitCelsius
        self.minChangeInterval = minChangeInterval
        self.maxPlausibleRPM = maxPlausibleRPM
        self.plausibleCelsius = plausibleCelsius
    }

    /// The limits, or nil when they cannot be trusted: non-finite, minimum <= 0 (the fan could
    /// stop), maximum below minimum, or maximum beyond any plausible fan.
    public func validated(_ limits: FanLimits?) -> FanLimits? {
        guard let l = limits, l.minRPM.isFinite, l.maxRPM.isFinite,
              l.minRPM > 0, l.maxRPM >= l.minRPM, l.maxRPM <= maxPlausibleRPM else { return nil }
        return l
    }

    /// Slider range for a fan, nil when its limits are not trusted.
    public func range(for limits: FanLimits?) -> ClosedRange<Double>? {
        guard let l = validated(limits) else { return nil }
        return l.minRPM...l.maxRPM
    }

    /// `rpm` clamped into the limits; nil for NaN or infinity.
    public func clamp(_ rpm: Double, to limits: FanLimits) -> Double? {
        guard rpm.isFinite else { return nil }
        return Swift.min(Swift.max(rpm, limits.minRPM), limits.maxRPM)
    }

    /// True when manual mode must not run: system thermal pressure serious or critical, hottest
    /// reading above the limit, or no plausible reading at all.
    public func mustForceAutomatic(_ thermal: ThermalSnapshot) -> Bool {
        if thermal.pressure == .serious || thermal.pressure == .critical { return true }
        guard let t = thermal.maxCelsius, t.isFinite, plausibleCelsius.contains(t) else { return true }
        return t > thermalLimitCelsius
    }

    /// Order matters: thermal first (a hot machine always gets automatic, whatever was asked),
    /// then fan index, SMC limits, the request value, and the rate limit.
    public func evaluate(fan: Int, requestedRPM: Double, limits: [Int: FanLimits], thermal: ThermalSnapshot,
                         lastChange: TimeInterval?, now: TimeInterval) -> FanDecision {
        if mustForceAutomatic(thermal) { return .forceAutomatic }
        guard let raw = limits[fan] else { return .reject(.unknownFan, retryAfter: nil) }
        guard let trusted = validated(raw) else { return .reject(.invalidLimits, retryAfter: nil) }
        guard let target = clamp(requestedRPM, to: trusted) else { return .reject(.invalidRequest, retryAfter: nil) }
        if let last = lastChange {
            let elapsed = now - last
            // Written so NaN and a clock that went backwards both count as "too soon".
            if !(elapsed >= minChangeInterval) {
                let wait = elapsed.isFinite && elapsed >= 0 ? minChangeInterval - elapsed : minChangeInterval
                return .reject(.rateLimited, retryAfter: wait)
            }
        }
        return .apply(fan: fan, rpm: target)
    }
}
