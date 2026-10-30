import Testing
@testable import FanShared

@Suite struct FanSafetyPolicyTests {
    let policy = FanSafetyPolicy()   // 95 C, 1 s between changes
    let limits = [0: FanLimits(minRPM: 2317, maxRPM: 7826), 1: FanLimits(minRPM: 2317, maxRPM: 7826)]
    let cool = ThermalSnapshot(maxCelsius: 60, pressure: .nominal)

    private func decide(_ rpm: Double, fan: Int = 0, thermal: ThermalSnapshot? = nil,
                        last: Double? = nil, now: Double = 100) -> FanDecision {
        policy.evaluate(fan: fan, requestedRPM: rpm, limits: limits, thermal: thermal ?? cool,
                        lastChange: last, now: now)
    }

    @Test func inRangeRequestIsApplied() {
        #expect(decide(3000) == .apply(fan: 0, rpm: 3000))
        #expect(decide(7826, fan: 1) == .apply(fan: 1, rpm: 7826))
        #expect(decide(2317) == .apply(fan: 0, rpm: 2317))
    }

    @Test func neverBelowManufacturerMinimum() {
        #expect(decide(1000) == .apply(fan: 0, rpm: 2317))
        #expect(decide(0) == .apply(fan: 0, rpm: 2317))
        #expect(decide(-5000) == .apply(fan: 0, rpm: 2317))
        #expect(decide(-.greatestFiniteMagnitude) == .apply(fan: 0, rpm: 2317))
    }

    @Test func neverAboveManufacturerMaximum() {
        #expect(decide(9000) == .apply(fan: 0, rpm: 7826))
        #expect(decide(1e12) == .apply(fan: 0, rpm: 7826))
        #expect(decide(.greatestFiniteMagnitude) == .apply(fan: 0, rpm: 7826))
    }

    @Test func nonFiniteRequestsAreRejected() {
        #expect(decide(.nan) == .reject(.invalidRequest, retryAfter: nil))
        #expect(decide(.infinity) == .reject(.invalidRequest, retryAfter: nil))
        #expect(decide(-.infinity) == .reject(.invalidRequest, retryAfter: nil))
        #expect(decide(.signalingNaN) == .reject(.invalidRequest, retryAfter: nil))
    }

    @Test func unknownFanIndexesAreRejected() {
        #expect(decide(3000, fan: 2) == .reject(.unknownFan, retryAfter: nil))
        #expect(decide(3000, fan: -1) == .reject(.unknownFan, retryAfter: nil))
        #expect(decide(3000, fan: Int.max) == .reject(.unknownFan, retryAfter: nil))
        #expect(decide(3000, fan: Int.min) == .reject(.unknownFan, retryAfter: nil))
    }

    @Test func implausibleSMCLimitsAreRejected() {
        let bad: [FanLimits] = [
            FanLimits(minRPM: 0, maxRPM: 7000),          // zero minimum: could stop the fan
            FanLimits(minRPM: -100, maxRPM: 7000),
            FanLimits(minRPM: 5000, maxRPM: 3000),       // inverted
            FanLimits(minRPM: .nan, maxRPM: 7000),
            FanLimits(minRPM: 2000, maxRPM: .infinity),
            FanLimits(minRPM: 2000, maxRPM: 50_000),     // beyond any laptop fan
        ]
        for l in bad {
            #expect(policy.validated(l) == nil)
            let d = policy.evaluate(fan: 0, requestedRPM: 3000, limits: [0: l], thermal: cool, lastChange: nil, now: 1)
            #expect(d == .reject(.invalidLimits, retryAfter: nil))
        }
        #expect(policy.validated(FanLimits(minRPM: 2317, maxRPM: 2317)) != nil)
    }

    @Test func rateLimitsChangesPerFan() {
        #expect(decide(3000, last: 99.5, now: 100) == .reject(.rateLimited, retryAfter: 0.5))
        #expect(decide(3000, last: 99, now: 100) == .apply(fan: 0, rpm: 3000))
        #expect(decide(3000, last: 98, now: 100) == .apply(fan: 0, rpm: 3000))
        // A clock that went backwards waits the full interval rather than letting a change through.
        #expect(decide(3000, last: 200, now: 100) == .reject(.rateLimited, retryAfter: 1))
        #expect(decide(3000, last: .nan, now: 100) == .reject(.rateLimited, retryAfter: 1))
    }

    @Test func thermalOverrideForcesAutomatic() {
        let hot = ThermalSnapshot(maxCelsius: 95.1, pressure: .nominal)
        #expect(decide(3000, thermal: hot) == .forceAutomatic)
        // Even a request that would otherwise be rejected yields automatic when hot.
        #expect(decide(3000, fan: 7, thermal: hot) == .forceAutomatic)
        #expect(decide(.nan, thermal: hot) == .forceAutomatic)
        #expect(decide(3000, thermal: ThermalSnapshot(maxCelsius: 95, pressure: .nominal)) == .apply(fan: 0, rpm: 3000))
    }

    @Test func systemThermalPressureForcesAutomatic() {
        #expect(decide(3000, thermal: ThermalSnapshot(maxCelsius: 50, pressure: .serious)) == .forceAutomatic)
        #expect(decide(3000, thermal: ThermalSnapshot(maxCelsius: 50, pressure: .critical)) == .forceAutomatic)
        #expect(decide(3000, thermal: ThermalSnapshot(maxCelsius: 50, pressure: .fair)) == .apply(fan: 0, rpm: 3000))
    }

    @Test func unknownOrImplausibleTemperatureFailsClosed() {
        for t: Double? in [nil, .nan, .infinity, -40, 0, 500] {
            #expect(policy.mustForceAutomatic(ThermalSnapshot(maxCelsius: t, pressure: .nominal)))
            #expect(decide(3000, thermal: ThermalSnapshot(maxCelsius: t, pressure: .nominal)) == .forceAutomatic)
        }
        #expect(!policy.mustForceAutomatic(cool))
    }

    @Test func clampIsTheSameRangeTheSliderShows() {
        let l = limits[0]!
        #expect(policy.clamp(1, to: l) == 2317)
        #expect(policy.clamp(99_999, to: l) == 7826)
        #expect(policy.clamp(.nan, to: l) == nil)
        #expect(policy.range(for: l) == 2317...7826)
        #expect(policy.range(for: FanLimits(minRPM: 0, maxRPM: 1)) == nil)
    }
}
