// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Lane W6C (fans, UI and policy). The lane owns this file.

import Foundation

/// The decision the ported fan policy takes at each tick, pure: no SMC, no helper, no clock.
///
/// Upstream's helper evaluated the curve itself. Ours is a thin root process that only knows "this fan at this speed",
/// so the evaluation happens here, in the app, with upstream's own curve maths (`FanControlPolicy`: interpolation,
/// 5 % steps, 2 degrees of hysteresis) and the safety rules written down below. The helper still enforces its own
/// limits underneath (clamp to the SMC range, 1 s between changes, 95 degrees, watchdog), so a bug here can only ask
/// for less than the helper would allow, never more.
enum FanControlEngine {
    /// The user's own ceiling: above it the app hands the fans back to macOS. The helper's hard limit is 95.
    static let defaultCeiling = 90.0
    static let ceilingRange: ClosedRange<Double> = 80...95
    /// UserDefaults key of the ceiling (Mac Island's own, not an upstream key).
    static let ceilingKey = "macIslandFanSafetyCeiling"

    static func sanitizedCeiling(_ value: Double) -> Double {
        guard value.isFinite else { return defaultCeiling }
        return min(max(value.rounded(), ceilingRange.lowerBound), ceilingRange.upperBound)
    }

    struct Input {
        var configuration: FanControlConfiguration
        var temperatures: [FanControlTemperatureReading]
        var fans: [FanControlFanReading]
        /// The level last applied on every fan, nil before the first apply.
        var appliedLevel: Int?
        /// The speed last asked for per fan (what we sent, not what the helper clamped it to).
        var appliedTargets: [Int: Double]
        var thermalState: ProcessInfo.ThermalState
        var ceilingCelsius: Double
        /// Consecutive ticks where a curve could not be evaluated (a sensor missing).
        var temperatureFailures: Int
    }

    enum Step: Equatable {
        /// Nothing to send.
        case hold
        /// Send these speeds, then remember the level.
        case apply(level: Int, targets: [Int: Double])
        /// Hand every fan back to macOS, for this reason.
        case restore(FanControlStopReason)
    }

    struct Result: Equatable {
        var step: Step
        var temperatureFailures: Int
    }

    static func evaluate(_ input: Input) -> Result {
        let failures = input.temperatureFailures
        // 1. The system says it is hot: macOS decides, whatever the curve says.
        if input.thermalState == .serious || input.thermalState == .critical {
            return Result(step: .restore(.thermalPressure), temperatureFailures: failures)
        }
        // 2. The user's ceiling, on any plausible reading. An implausible reading is ignored here (a curve that
        //    needs it fails closed below).
        let plausible = input.temperatures.map(\.celsius).filter(FanControlPolicy.validTemperature)
        if let hottest = plausible.max(), hottest >= sanitizedCeiling(input.ceilingCelsius) {
            return Result(step: .restore(.thermalPressure), temperatureFailures: failures)
        }
        // 3. The cooling level.
        let level: Int
        switch input.configuration.mode {
        case .system:
            return Result(step: .hold, temperatureFailures: 0)
        case .manual:
            guard FanControlPolicy.validCoolingLevel(input.configuration.manualLevel) else {
                return Result(step: .restore(.hardwareChanged), temperatureFailures: failures)
            }
            level = input.configuration.manualLevel
        case .curve:
            guard let requested = FanControlPolicy.curveCoolingLevel(
                curves: input.configuration.curves, temperatures: input.temperatures,
                previousLevel: input.appliedLevel) else {
                // A missing sensor does not hold the fans forced for ever: three misses and macOS takes over.
                let misses = failures + 1
                if misses >= FanControlPolicy.temperatureFailureLimit {
                    return Result(step: .restore(.temperatureUnavailable), temperatureFailures: misses)
                }
                return Result(step: .hold, temperatureFailures: misses)
            }
            level = requested
        }
        // 4. Speeds from each fan's own SMC range. A range that cannot be trusted is a changed machine.
        guard let targets = targets(level: level, fans: input.fans) else {
            return Result(step: .restore(.hardwareChanged), temperatureFailures: 0)
        }
        if level == input.appliedLevel, targets.allSatisfy({ fan, rpm in
            input.appliedTargets[fan].map { FanControlPolicy.targetRPMMatches(target: $0, expected: rpm) } ?? false
        }) {
            return Result(step: .hold, temperatureFailures: 0)
        }
        return Result(step: .apply(level: level, targets: targets), temperatureFailures: 0)
    }

    /// One speed per fan for a level: `minimum + (maximum - minimum) * level / 100`, nil when there is no fan or one
    /// fan has bounds `FanControlPolicy` refuses. Level 0 is the fan's minimum, never zero.
    static func targets(level: Int, fans: [FanControlFanReading]) -> [Int: Double]? {
        guard !fans.isEmpty else { return nil }
        var result: [Int: Double] = [:]
        for fan in fans {
            guard let rpm = FanControlPolicy.coolingTargetRPM(
                minimum: fan.minimumRPM, maximum: fan.maximumRPM, level: level) else { return nil }
            result[fan.index] = rpm.rounded()
        }
        return result
    }
}

/// Ready-made curves for the settings page. Every one passes `FanControlPolicy.validCurves`, and none leaves a fan
/// below its own minimum (level 0 is the minimum, not a stop).
enum FanCurvePreset: String, CaseIterable, Identifiable {
    case quiet, balanced, cool, maximum

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quiet: "Silencieux"
        case .balanced: "Équilibré"
        case .cool: "Frais"
        case .maximum: "Maximum"
        }
    }

    var summary: String {
        switch self {
        case .quiet: "Ventilos au minimum jusqu'à 55 °C, puis progressif."
        case .balanced: "Monte à partir de 50 °C, plein régime vers 90 °C."
        case .cool: "Démarre tôt (45 °C) pour garder le Mac frais."
        case .maximum: "Plein régime tout de suite : bruyant, pour une charge longue."
        }
    }

    var symbol: String {
        switch self {
        case .quiet: "moon.fill"
        case .balanced: "scalemass.fill"
        case .cool: "snowflake"
        case .maximum: "fanblades.fill"
        }
    }

    /// (temperature in degrees, cooling level in percent), strictly rising temperatures and non-decreasing levels.
    private var points: [(Int, Int)] {
        switch self {
        case .quiet: [(55, 0), (70, 25), (85, 60), (95, 100)]
        case .balanced: [(50, 0), (65, 30), (78, 65), (90, 100)]
        case .cool: [(45, 10), (58, 40), (70, 75), (80, 100)]
        case .maximum: [(40, 100), (60, 100)]
        }
    }

    var curves: [FanControlCurve] {
        [FanControlCurve(sensor: .hottestSoC,
                         points: points.map { FanControlCurvePoint(temperature: $0.0, coolingLevel: $0.1) })]
    }
}
