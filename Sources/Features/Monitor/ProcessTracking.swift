import Foundation

/// A process after delta computation. `cpuPercent` is `nil` until a baseline exists for the pid.
struct ProcessStat: Equatable, Sendable {
    var pid: Int32
    var cpuPercent: Double?
    var residentBytes: UInt64
}

/// What the view lists: name resolved for the top few only.
struct ProcessUsage: Identifiable, Equatable, Sendable {
    var pid: Int32
    var name: String
    var cpuPercent: Double?
    var residentBytes: UInt64
    var id: Int32 { pid }
}

/// Keeps the previous CPU time of every pid to turn cumulative times into percentages.
struct ProcessCPUTracker {
    private var previous: [Int32: UInt64] = [:]
    private var scratch: [Int32: UInt64] = [:]
    private var previousNowNs: UInt64?

    var trackedCount: Int { previous.count }

    mutating func reset() {
        previous.removeAll(keepingCapacity: true)
        previousNowNs = nil
    }

    mutating func update(_ raws: [ProcessRaw], nowNs: UInt64) -> [ProcessStat] {
        let wall: UInt64? = previousNowNs.flatMap { nowNs > $0 ? nowNs - $0 : nil }
        var out: [ProcessStat] = []
        out.reserveCapacity(raws.count)
        scratch.removeAll(keepingCapacity: true)
        for raw in raws {
            var percent: Double?
            if let wall, let before = previous[raw.pid] {
                percent = UsageMath.processCPUPercent(previousNs: before, currentNs: raw.cpuTimeNs, wallNs: wall)
            }
            scratch[raw.pid] = raw.cpuTimeNs
            out.append(ProcessStat(pid: raw.pid, cpuPercent: percent, residentBytes: raw.residentBytes))
        }
        swap(&previous, &scratch)
        previousNowNs = nowNs
        return out
    }
}

enum ProcessRanking {
    static func topByCPU(_ stats: [ProcessStat], limit: Int) -> [ProcessStat] {
        guard limit > 0 else { return [] }
        return Array(stats.filter { $0.cpuPercent != nil }
            .sorted {
                let a = $0.cpuPercent ?? 0, b = $1.cpuPercent ?? 0
                return a != b ? a > b : $0.pid < $1.pid
            }
            .prefix(limit))
    }

    static func topByMemory(_ stats: [ProcessStat], limit: Int) -> [ProcessStat] {
        guard limit > 0 else { return [] }
        return Array(stats.sorted {
            $0.residentBytes != $1.residentBytes ? $0.residentBytes > $1.residentBytes : $0.pid < $1.pid
        }.prefix(limit))
    }
}
