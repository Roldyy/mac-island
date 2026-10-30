import Darwin
import Foundation

/// CPU ticks through `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`.
final class MachCPUSampler: CPUSampling {
    /// `mach_host_self()` adds a port right on every call: take it once.
    private let host = mach_host_self()

    func ticks() -> [CPUTicks]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let kr = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard kr == KERN_SUCCESS, let info else { return nil }
        defer {
            // The kernel allocated this array in our address space.
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        let states = Int(CPU_STATE_MAX)
        var out: [CPUTicks] = []
        out.reserveCapacity(Int(cpuCount))
        for core in 0..<Int(cpuCount) {
            let base = core * states
            out.append(CPUTicks(
                user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])))
        }
        return out
    }
}

/// Memory through `host_statistics64(HOST_VM_INFO64)` and the pressure sysctl.
final class MachMemorySampler: MemorySampling {
    private let host = mach_host_self()
    private let pageSize = UInt64(max(4096, sysconf(_SC_PAGESIZE)))
    private let totalBytes = ProcessInfo.processInfo.physicalMemory

    func read() -> MemoryCounts? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride
                                           / MemoryLayout<integer_t>.stride)
        let capacity = Int(count)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return MemoryCounts(internalPages: UInt64(stats.internal_page_count),
                            purgeablePages: UInt64(stats.purgeable_count),
                            wiredPages: UInt64(stats.wire_count),
                            compressorPages: UInt64(stats.compressor_page_count),
                            pageSize: pageSize,
                            totalBytes: totalBytes)
    }

    func pressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .unknown
        }
        return MemoryPressure(sysctlValue: level)
    }
}

struct ProcessThermalSampler: ThermalSampling {
    func level() -> ThermalLevel { ThermalLevel(ProcessInfo.processInfo.thermalState) }
}

/// Per-process CPU time and resident size through `proc_listpids` + `proc_pidinfo(PROC_PIDTASKINFO)`.
/// Processes we are not allowed to inspect (other users, protected) are skipped silently.
final class MachProcessSampler: ProcessSampling {
    private var pidBuffer: [pid_t] = []
    private let timebase: (numer: UInt64, denom: UInt64)

    init() {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        timebase = (UInt64(max(1, tb.numer)), UInt64(max(1, tb.denom)))
    }

    /// Task CPU times are in mach absolute time units; on Apple Silicon that is not nanoseconds.
    private func nanoseconds(_ ticks: UInt64) -> UInt64 {
        ticks / timebase.denom * timebase.numer + (ticks % timebase.denom) * timebase.numer / timebase.denom
    }

    func snapshot() -> [ProcessRaw] {
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { return [] }
        let slots = Int(needed) / MemoryLayout<pid_t>.stride + 32
        if pidBuffer.count < slots { pidBuffer = [pid_t](repeating: 0, count: slots) }
        let bytes = pidBuffer.withUnsafeMutableBytes {
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, $0.baseAddress, Int32($0.count))
        }
        guard bytes > 0 else { return [] }
        let count = Int(bytes) / MemoryLayout<pid_t>.stride
        var out: [ProcessRaw] = []
        out.reserveCapacity(count)
        var info = proc_taskinfo()
        let infoSize = Int32(MemoryLayout<proc_taskinfo>.stride)
        for i in 0..<count {
            let pid = pidBuffer[i]
            guard pid > 0 else { continue }
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, infoSize) == infoSize else { continue }
            out.append(ProcessRaw(pid: pid,
                                  cpuTimeNs: nanoseconds(info.pti_total_user &+ info.pti_total_system),
                                  residentBytes: info.pti_resident_size))
        }
        return out
    }

    func name(pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 128)
        let n = proc_name(pid, &buffer, UInt32(buffer.count))
        guard n > 0 else { return "?" }
        return String(decoding: buffer.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
