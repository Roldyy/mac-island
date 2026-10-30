import Testing
@testable import MonitorFeature

@Suite struct UsageMathTests {
    private func t(_ user: UInt32, _ system: UInt32, _ idle: UInt32, _ nice: UInt32 = 0) -> CPUTicks {
        CPUTicks(user: user, system: system, idle: idle, nice: nice)
    }

    @Test func halfBusyCore() {
        let usage = UsageMath.coreUsage(previous: t(0, 0, 0), current: t(30, 20, 50))
        #expect(usage == 50)
    }

    @Test func niceCountsAsBusy() {
        let usage = UsageMath.coreUsage(previous: t(0, 0, 0, 0), current: t(0, 0, 50, 50))
        #expect(usage == 50)
    }

    @Test func noTicksElapsedIsUnknown() {
        #expect(UsageMath.coreUsage(previous: t(5, 5, 5), current: t(5, 5, 5)) == nil)
    }

    @Test func counterWraparoundIsHandled() {
        // idle wraps from near UInt32.max to a small number: delta is 16, not a huge negative.
        let prev = t(100, 0, UInt32.max - 5)
        let cur = t(116, 0, 10)
        // busy delta 16, idle delta 16 (max-5 -> 10 is 16 ticks) => 50 %
        #expect(UsageMath.coreUsage(previous: prev, current: cur) == 50)
    }

    @Test func totalIsWeightedBySumOfTicksNotMeanOfPercentages() {
        let prev = [t(0, 0, 0), t(0, 0, 0)]
        // core 0: 10 busy of 10 (100 %), core 1: 0 busy of 90 (0 %) => 10 / 100 = 10 %
        let cur = [t(10, 0, 0), t(0, 0, 90)]
        #expect(UsageMath.cpuUsage(previous: prev, current: cur) == 10)
    }

    @Test func coreCountChangeIsUnknown() {
        #expect(UsageMath.cpuUsage(previous: [t(0, 0, 0)], current: [t(1, 0, 1), t(1, 0, 1)]) == nil)
        #expect(UsageMath.cpuUsage(previous: [], current: []) == nil)
    }

    @Test func perCoreUsage() {
        let prev = [t(0, 0, 0), t(0, 0, 0)]
        let cur = [t(25, 0, 75), t(100, 0, 0)]
        #expect(UsageMath.perCoreUsage(previous: prev, current: cur) == [25, 100])
    }

    @Test func perCoreSkipsNothingWhenOneCoreIdleTicksAreZero() {
        let prev = [t(0, 0, 0), t(0, 0, 0)]
        let cur = [t(25, 0, 75), t(0, 0, 0)]
        // The second core had no ticks: reported as 0, not dropped, so indexes stay aligned.
        #expect(UsageMath.perCoreUsage(previous: prev, current: cur) == [25, 0])
    }

    @Test func memoryUsedFollowsActivityMonitorFormula() {
        let c = MemoryCounts(internalPages: 1000, purgeablePages: 200, wiredPages: 300, compressorPages: 100,
                             pageSize: 16_384, totalBytes: 16_384 * 4000)
        // (1000 - 200) + 300 + 100 = 1200 pages
        #expect(UsageMath.usedBytes(c) == 1200 * 16_384)
        #expect(UsageMath.memoryUsedPercent(c) == 30)
    }

    @Test func purgeableLargerThanInternalNeverUnderflows() {
        let c = MemoryCounts(internalPages: 10, purgeablePages: 50, wiredPages: 5, compressorPages: 5,
                             pageSize: 4096, totalBytes: 4096 * 100)
        // internal 10 kept as is, + wired 5 + compressor 5
        #expect(UsageMath.usedBytes(c) == 20 * 4096)
    }

    @Test func memoryPercentIsClampedAndSafeWithZeroTotal() {
        let over = MemoryCounts(internalPages: 500, purgeablePages: 0, wiredPages: 0, compressorPages: 0,
                                pageSize: 1, totalBytes: 100)
        #expect(UsageMath.memoryUsedPercent(over) == 100)
        let none = MemoryCounts(internalPages: 1, purgeablePages: 0, wiredPages: 0, compressorPages: 0,
                                pageSize: 1, totalBytes: 0)
        #expect(UsageMath.memoryUsedPercent(none) == 0)
    }

    @Test func processCPUPercentIsPerCore() {
        // 500 ms of CPU in 1 s wall = 50 %; 2 s of CPU in 1 s wall = 200 % (two cores).
        #expect(UsageMath.processCPUPercent(previousNs: 0, currentNs: 500_000_000, wallNs: 1_000_000_000) == 50)
        #expect(UsageMath.processCPUPercent(previousNs: 0, currentNs: 2_000_000_000, wallNs: 1_000_000_000) == 200)
    }

    @Test func processCPUPercentGuardsBadInput() {
        #expect(UsageMath.processCPUPercent(previousNs: 0, currentNs: 5, wallNs: 0) == nil)
        // A counter that went backwards (pid reuse) is unknown, never negative.
        #expect(UsageMath.processCPUPercent(previousNs: 900, currentNs: 100, wallNs: 1_000) == nil)
    }
}
