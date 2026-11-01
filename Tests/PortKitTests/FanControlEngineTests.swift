import Foundation
import Testing
@testable import PortKit

/// Lane W6C: the pure decisions of the ported fan policy. No SMC, no helper, no clock.
@Suite struct FanControlEngineTests {
    static let fans = [
        FanControlFanReading(index: 0, actualRPM: 2300, minimumRPM: 2317, maximumRPM: 7826, targetRPM: 2317,
                             isManuallyControlled: false),
        FanControlFanReading(index: 1, actualRPM: 2400, minimumRPM: 2000, maximumRPM: 6000, targetRPM: 2000,
                             isManuallyControlled: false),
    ]

    static func input(_ configuration: FanControlConfiguration, soc: Double? = 60, applied: Int? = nil,
                      targets: [Int: Double] = [:], thermal: ProcessInfo.ThermalState = .nominal,
                      ceiling: Double = 90, failures: Int = 0,
                      fans: [FanControlFanReading] = FanControlEngineTests.fans) -> FanControlEngine.Input {
        FanControlEngine.Input(
            configuration: configuration,
            temperatures: soc.map { [FanControlTemperatureReading(source: .hottestSoC, celsius: $0)] } ?? [],
            fans: fans, appliedLevel: applied, appliedTargets: targets, thermalState: thermal,
            ceilingCelsius: ceiling, temperatureFailures: failures)
    }

    static let curve = FanControlConfiguration.curve([FanControlConfiguration.defaultCurve])

    // MARK: Levels and speeds

    @Test func aManualLevelBecomesOneSpeedPerFanInItsOwnRange() {
        let result = FanControlEngine.evaluate(Self.input(.manual(level: 50)))
        guard case .apply(let level, let targets) = result.step else { Issue.record("expected apply"); return }
        #expect(level == 50)
        #expect(targets[0] == (2317 + (7826 - 2317) * 0.5).rounded())
        #expect(targets[1] == 4000)
    }

    @Test func levelZeroIsTheFanMinimumNeverAStop() {
        let result = FanControlEngine.evaluate(Self.input(.manual(level: 0)))
        guard case .apply(_, let targets) = result.step else { Issue.record("expected apply"); return }
        #expect(targets == [0: 2317, 1: 2000])
    }

    @Test func aCurveReadsTheLevelFromTheTemperature() {
        // Default curve: 50 degrees -> 0 %, 70 degrees -> 100 %: 60 degrees is 50 %.
        guard case .apply(let level, _) = FanControlEngine.evaluate(Self.input(Self.curve, soc: 60)).step else {
            Issue.record("expected apply"); return
        }
        #expect(level == 50)
    }

    @Test func theSameLevelAndSpeedsSendNothingAgain() {
        let first = FanControlEngine.evaluate(Self.input(.manual(level: 50)))
        guard case .apply(let level, let targets) = first.step else { Issue.record("expected apply"); return }
        let again = FanControlEngine.evaluate(Self.input(.manual(level: 50), applied: level, targets: targets))
        #expect(again.step == .hold)
    }

    @Test func aFanThatHasNoSpeedYetGetsOneEvenAtTheSameLevel() {
        let again = FanControlEngine.evaluate(Self.input(.manual(level: 50), applied: 50, targets: [0: 5072]))
        guard case .apply = again.step else { Issue.record("fan 1 was never sent"); return }
    }

    @Test func coolingDownHoldsTheLevelUntilTheHysteresisIsCrossed() {
        // 61 degrees = 55 %. At 60 degrees the request is 50 %, but 2 degrees warmer would still ask 60 %: hold.
        let sent = FanControlEngine.targets(level: 55, fans: Self.fans) ?? [:]
        let held = FanControlEngine.evaluate(Self.input(Self.curve, soc: 60, applied: 55, targets: sent))
        #expect(held.step == .hold)
        // 55 degrees is 25 %; 2 degrees warmer is 35 %, below the applied 55 %: the level follows down.
        guard case .apply(let level, _) = FanControlEngine.evaluate(
            Self.input(Self.curve, soc: 55, applied: 55, targets: sent)).step else {
            Issue.record("expected apply"); return
        }
        #expect(level == 35)
    }

    // MARK: Safety

    @Test func seriousOrCriticalThermalPressureHandsBack() {
        for state in [ProcessInfo.ThermalState.serious, .critical] {
            let result = FanControlEngine.evaluate(Self.input(.manual(level: 100), thermal: state))
            #expect(result.step == .restore(.thermalPressure))
        }
        #expect(FanControlEngine.evaluate(Self.input(.manual(level: 100), thermal: .fair)).step != .restore(.thermalPressure))
    }

    @Test func theUserCeilingHandsBackAtTheCeilingNotBelow() {
        #expect(FanControlEngine.evaluate(Self.input(.manual(level: 100), soc: 89.9, ceiling: 90)).step
                != .restore(.thermalPressure))
        #expect(FanControlEngine.evaluate(Self.input(.manual(level: 100), soc: 90, ceiling: 90)).step
                == .restore(.thermalPressure))
        #expect(FanControlEngine.evaluate(Self.input(Self.curve, soc: 85, ceiling: 85)).step == .restore(.thermalPressure))
    }

    @Test func theCeilingIsKeptInItsRangeWhateverIsStored() {
        #expect(FanControlEngine.sanitizedCeiling(10) == 80)
        #expect(FanControlEngine.sanitizedCeiling(200) == 95)
        #expect(FanControlEngine.sanitizedCeiling(.nan) == FanControlEngine.defaultCeiling)
        #expect(FanControlEngine.sanitizedCeiling(.infinity) == FanControlEngine.defaultCeiling)
        // A stored ceiling of 10 must not hand the fans back at once for ever: it reads as 80.
        #expect(FanControlEngine.evaluate(Self.input(.manual(level: 100), soc: 70, ceiling: 10)).step
                != .restore(.thermalPressure))
    }

    @Test func aMissingSensorHoldsTwiceThenHandsBackOnTheThird() {
        let one = FanControlEngine.evaluate(Self.input(Self.curve, soc: nil, failures: 0))
        #expect(one.step == .hold && one.temperatureFailures == 1)
        let two = FanControlEngine.evaluate(Self.input(Self.curve, soc: nil, failures: 1))
        #expect(two.step == .hold && two.temperatureFailures == 2)
        let three = FanControlEngine.evaluate(Self.input(Self.curve, soc: nil, failures: 2))
        #expect(three.step == .restore(.temperatureUnavailable))
    }

    @Test func aGoodReadingResetsTheMissCounter() {
        let result = FanControlEngine.evaluate(Self.input(Self.curve, soc: 60, failures: 2))
        #expect(result.temperatureFailures == 0)
    }

    @Test func aNonsenseTemperatureCountsAsMissingForACurve() {
        for bad in [0.0, -4, 300, .nan, .infinity] {
            let result = FanControlEngine.evaluate(Self.input(Self.curve, soc: bad, failures: 2))
            #expect(result.step == .restore(.temperatureUnavailable), "\(bad)")
        }
    }

    @Test func fansWhoseRangeCannotBeTrustedHandBack() {
        let broken = [FanControlFanReading(index: 0, actualRPM: 1, minimumRPM: 0, maximumRPM: 0, targetRPM: 0,
                                           isManuallyControlled: false)]
        #expect(FanControlEngine.evaluate(Self.input(.manual(level: 50), fans: broken)).step == .restore(.hardwareChanged))
        #expect(FanControlEngine.evaluate(Self.input(.manual(level: 50), fans: [])).step == .restore(.hardwareChanged))
        let huge = [FanControlFanReading(index: 0, actualRPM: 1, minimumRPM: 1000, maximumRPM: 99_999, targetRPM: 0,
                                         isManuallyControlled: false)]
        #expect(FanControlEngine.evaluate(Self.input(.manual(level: 50), fans: huge)).step == .restore(.hardwareChanged))
    }

    @Test func anInvalidManualLevelNeverReachesAFan() {
        let bad = FanControlConfiguration(mode: .manual, manualLevel: 37, curves: [])
        #expect(FanControlEngine.evaluate(Self.input(bad)).step == .restore(.hardwareChanged))
    }

    @Test func theSystemModeSendsNothing() {
        let system = FanControlConfiguration(mode: .system, manualLevel: 100, curves: [])
        #expect(FanControlEngine.evaluate(Self.input(system)).step == .hold)
    }

    // MARK: Presets

    @Test func everyPresetIsAValidCurveThatEvaluatesToAValidLevel() {
        #expect(FanCurvePreset.allCases.count == 4)
        for preset in FanCurvePreset.allCases {
            #expect(FanControlPolicy.validCurves(preset.curves), "\(preset.title)")
            #expect(FanControlConfiguration.decodeCurves(FanControlConfiguration.encodeCurves(preset.curves) ?? "") != nil)
            for temperature in stride(from: 20.0, through: 110.0, by: 5) {
                let level = FanControlPolicy.curveCoolingLevel(
                    curves: preset.curves,
                    temperatures: [FanControlTemperatureReading(source: .hottestSoC, celsius: temperature)])
                #expect(level.map(FanControlPolicy.validCoolingLevel) == true, "\(preset.title) at \(temperature)")
            }
            #expect(!preset.title.isEmpty && !preset.summary.isEmpty)
        }
    }

    @Test func presetsAreOrderedFromQuietToMaximum() {
        func level(_ preset: FanCurvePreset, at temperature: Double) -> Int {
            FanControlPolicy.curveCoolingLevel(
                curves: preset.curves,
                temperatures: [FanControlTemperatureReading(source: .hottestSoC, celsius: temperature)]) ?? -1
        }
        for temperature in [50.0, 60, 70] {
            #expect(level(.quiet, at: temperature) <= level(.balanced, at: temperature))
            #expect(level(.balanced, at: temperature) <= level(.cool, at: temperature))
            #expect(level(.cool, at: temperature) <= level(.maximum, at: temperature))
        }
        #expect(level(.maximum, at: 45) == 100)
    }
}
