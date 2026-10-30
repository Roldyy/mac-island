import Foundation

/// Cumulative tick counters of one core, as `host_processor_info` reports them (32-bit, they wrap).
struct CPUTicks: Equatable, Sendable {
    var user: UInt32
    var system: UInt32
    var idle: UInt32
    var nice: UInt32
}

/// Page counters from `host_statistics64`, already scaled to what the formula needs.
struct MemoryCounts: Equatable, Sendable {
    var internalPages: UInt64
    var purgeablePages: UInt64
    var wiredPages: UInt64
    var compressorPages: UInt64
    var pageSize: UInt64
    var totalBytes: UInt64
}

/// Pure delta and percentage computations. No system call in here.
enum UsageMath {
    /// Busy share of one core between two readings, 0...100. `nil` when no tick elapsed.
    /// Wrapping subtraction: a counter that wrapped past `UInt32.max` still gives the right delta.
    static func coreUsage(previous: CPUTicks, current: CPUTicks) -> Double? {
        let (busy, total) = deltas(previous, current)
        guard total > 0 else { return nil }
        return Double(busy) * 100 / Double(total)
    }

    /// Whole-machine usage: busy ticks over all ticks of all cores (not a mean of percentages).
    static func cpuUsage(previous: [CPUTicks], current: [CPUTicks]) -> Double? {
        guard !previous.isEmpty, previous.count == current.count else { return nil }
        var busy: UInt64 = 0, total: UInt64 = 0
        for i in previous.indices {
            let d = deltas(previous[i], current[i])
            busy += d.busy
            total += d.total
        }
        guard total > 0 else { return nil }
        return Double(busy) * 100 / Double(total)
    }

    /// One value per core, index-aligned; a core with no elapsed tick reads 0.
    static func perCoreUsage(previous: [CPUTicks], current: [CPUTicks]) -> [Double]? {
        guard !previous.isEmpty, previous.count == current.count else { return nil }
        return previous.indices.map { coreUsage(previous: previous[$0], current: current[$0]) ?? 0 }
    }

    private static func deltas(_ p: CPUTicks, _ c: CPUTicks) -> (busy: UInt64, total: UInt64) {
        let user = UInt64(c.user &- p.user)
        let system = UInt64(c.system &- p.system)
        let nice = UInt64(c.nice &- p.nice)
        let idle = UInt64(c.idle &- p.idle)
        let busy = user + system + nice
        return (busy, busy + idle)
    }

    /// Activity Monitor's "Memory Used": app memory (anonymous minus purgeable) + wired + compressed.
    static func usedBytes(_ c: MemoryCounts) -> UInt64 {
        // purgeable > internal cannot happen on a healthy kernel; keep `internal` rather than underflow.
        let appPages = c.internalPages >= c.purgeablePages ? c.internalPages - c.purgeablePages : c.internalPages
        return (appPages + c.wiredPages + c.compressorPages) * c.pageSize
    }

    static func memoryUsedPercent(_ c: MemoryCounts) -> Double {
        guard c.totalBytes > 0 else { return 0 }
        return min(100, Double(usedBytes(c)) * 100 / Double(c.totalBytes))
    }

    /// CPU time of one process over a wall-clock window, in percent of ONE core (can exceed 100).
    static func processCPUPercent(previousNs: UInt64, currentNs: UInt64, wallNs: UInt64) -> Double? {
        guard wallNs > 0, currentNs >= previousNs else { return nil }
        return Double(currentNs - previousNs) * 100 / Double(wallNs)
    }
}
