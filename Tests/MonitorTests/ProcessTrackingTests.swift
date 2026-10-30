import Testing
@testable import MonitorFeature

@Suite struct ProcessTrackingTests {
    private func raw(_ pid: Int32, cpuMs: UInt64, rssMB: UInt64) -> ProcessRaw {
        ProcessRaw(pid: pid, cpuTimeNs: cpuMs * 1_000_000, residentBytes: rssMB * 1_048_576)
    }

    @Test func firstUpdateHasNoCPUBaseline() {
        var tracker = ProcessCPUTracker()
        let stats = tracker.update([raw(1, cpuMs: 100, rssMB: 10)], nowNs: 1_000_000_000)
        #expect(stats.count == 1)
        #expect(stats[0].cpuPercent == nil)
        #expect(stats[0].residentBytes == 10 * 1_048_576)
    }

    @Test func secondUpdateComputesPercentFromDelta() {
        var tracker = ProcessCPUTracker()
        _ = tracker.update([raw(1, cpuMs: 100, rssMB: 10), raw(2, cpuMs: 0, rssMB: 5)], nowNs: 1_000_000_000)
        let stats = tracker.update([raw(1, cpuMs: 600, rssMB: 10), raw(2, cpuMs: 0, rssMB: 5)], nowNs: 2_000_000_000)
        #expect(stats.first { $0.pid == 1 }?.cpuPercent == 50)
        #expect(stats.first { $0.pid == 2 }?.cpuPercent == 0)
    }

    @Test func newPidInLaterUpdateHasNoPercent() {
        var tracker = ProcessCPUTracker()
        _ = tracker.update([raw(1, cpuMs: 0, rssMB: 1)], nowNs: 1_000_000_000)
        let stats = tracker.update([raw(1, cpuMs: 0, rssMB: 1), raw(9, cpuMs: 800, rssMB: 1)], nowNs: 2_000_000_000)
        #expect(stats.first { $0.pid == 9 }?.cpuPercent == nil)
    }

    @Test func goneProcessesAreForgotten() {
        var tracker = ProcessCPUTracker()
        _ = tracker.update([raw(1, cpuMs: 0, rssMB: 1), raw(2, cpuMs: 0, rssMB: 1)], nowNs: 1_000_000_000)
        _ = tracker.update([raw(1, cpuMs: 0, rssMB: 1)], nowNs: 2_000_000_000)
        #expect(tracker.trackedCount == 1)
    }

    @Test func resetDropsTheBaseline() {
        var tracker = ProcessCPUTracker()
        _ = tracker.update([raw(1, cpuMs: 0, rssMB: 1)], nowNs: 1_000_000_000)
        tracker.reset()
        let stats = tracker.update([raw(1, cpuMs: 500, rssMB: 1)], nowNs: 2_000_000_000)
        #expect(stats[0].cpuPercent == nil)
    }

    @Test func topByCPUSortsDescendingAndSkipsUnknown() {
        let stats = [
            ProcessStat(pid: 1, cpuPercent: 5, residentBytes: 1),
            ProcessStat(pid: 2, cpuPercent: 80, residentBytes: 1),
            ProcessStat(pid: 3, cpuPercent: nil, residentBytes: 1),
            ProcessStat(pid: 4, cpuPercent: 40, residentBytes: 1),
        ]
        #expect(ProcessRanking.topByCPU(stats, limit: 2).map(\.pid) == [2, 4])
        #expect(ProcessRanking.topByCPU(stats, limit: 10).map(\.pid) == [2, 4, 1])
    }

    @Test func topByMemorySortsDescendingWithStablePidTieBreak() {
        let stats = [
            ProcessStat(pid: 7, cpuPercent: nil, residentBytes: 100),
            ProcessStat(pid: 3, cpuPercent: nil, residentBytes: 100),
            ProcessStat(pid: 5, cpuPercent: nil, residentBytes: 900),
        ]
        #expect(ProcessRanking.topByMemory(stats, limit: 3).map(\.pid) == [5, 3, 7])
    }

    @Test func limitZeroIsEmpty() {
        #expect(ProcessRanking.topByCPU([ProcessStat(pid: 1, cpuPercent: 1, residentBytes: 1)], limit: 0).isEmpty)
    }
}
