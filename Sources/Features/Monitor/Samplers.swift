import Foundation

/// Samplers sit behind protocols so the model is tested with scripted fakes.

enum MemoryPressure: Equatable, Sendable {
    case normal, warning, critical, unknown

    /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warn, 4 critical
    /// (the values of `DISPATCH_MEMORYPRESSURE_*`).
    init(sysctlValue: Int32) {
        switch sysctlValue {
        case 1: self = .normal
        case 2: self = .warning
        case 4: self = .critical
        default: self = .unknown
        }
    }
}

enum ThermalLevel: Equatable, Sendable {
    case nominal, fair, serious, critical

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .nominal
        }
    }
}

/// One process, as cheap as possible: no name (resolved later for the top few only).
struct ProcessRaw: Equatable, Sendable {
    var pid: Int32
    /// User + system CPU time since the process started, in nanoseconds.
    var cpuTimeNs: UInt64
    var residentBytes: UInt64
}

protocol CPUSampling {
    /// Per-core cumulative ticks, or `nil` when the kernel call failed.
    func ticks() -> [CPUTicks]?
}

protocol MemorySampling {
    func read() -> MemoryCounts?
    func pressure() -> MemoryPressure
}

protocol ThermalSampling {
    func level() -> ThermalLevel
}

protocol ProcessSampling {
    func snapshot() -> [ProcessRaw]
    /// Process name only (never a command line); `"?"` when it vanished or is not readable.
    func name(pid: Int32) -> String
}
