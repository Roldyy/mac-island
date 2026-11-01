import Darwin
import Foundation
import IslandKit

/// The system calls behind the samplers. Each one is cheap (a few microseconds), needs no permission and
/// returns nil on failure rather than a wrong number. Nothing here posts anything.
enum SystemCounters {
    // `mach_host_self()` adds a port reference on every call; one is enough.
    private static let host = mach_host_self()

    /// Ticks of every core since boot, from `host_processor_info`.
    static func cpuTicks() -> CPUTicks? {
        var cores: natural_t = 0
        var info: processor_info_array_t?
        var count: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cores, &info, &count) == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        var busy: UInt64 = 0, total: UInt64 = 0
        let states = Int(CPU_STATE_MAX)
        for core in 0..<Int(cores) {
            let user = UInt64(UInt32(bitPattern: info[core * states + Int(CPU_STATE_USER)]))
            let system = UInt64(UInt32(bitPattern: info[core * states + Int(CPU_STATE_SYSTEM)]))
            let nice = UInt64(UInt32(bitPattern: info[core * states + Int(CPU_STATE_NICE)]))
            let idle = UInt64(UInt32(bitPattern: info[core * states + Int(CPU_STATE_IDLE)]))
            busy += user + system + nice
            total += user + system + nice + idle
        }
        return CPUTicks(busy: busy, total: total)
    }

    /// Memory in use the way Activity Monitor adds it up: app memory + wired + compressed, from `host_statistics64`.
    static func usedMemory() -> UInt64? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let app = UInt64(stats.internal_page_count) &- UInt64(min(stats.purgeable_count, stats.internal_page_count))
        let pages = app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return pages * UInt64(getpagesize())
    }

    /// `kern.memorystatus_vm_pressure_level`: the kernel's own verdict (1 normal, 2 warning, 4 critical).
    static func memoryPressure() -> MemoryPressure {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        return MemoryPressure(level: Int(level))
    }

    /// Space the system offers for new files on the startup volume (what Finder calls "available").
    static func diskFreeBytes() -> UInt64? {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        else { return nil }
        if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 { return UInt64(important) }
        return values.volumeAvailableCapacity.map { UInt64(max($0, 0)) }
    }

    /// One pass of `getifaddrs`: flags, IPv4 presence and byte counters, merged per interface name.
    static func interfaces() -> [InterfaceReading] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var byName: [String: InterfaceReading] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let name = String(cString: entry.pointee.ifa_name)
            let flags = Int32(entry.pointee.ifa_flags)
            var reading = byName[name] ?? InterfaceReading(name: name, isUp: false, hasIPv4: false, counters: nil)
            reading.isUp = (flags & IFF_UP) != 0 && (flags & IFF_RUNNING) != 0
            switch Int32(entry.pointee.ifa_addr?.pointee.sa_family ?? 0) {
            case AF_INET:
                reading.hasIPv4 = true
            case AF_LINK:
                if let data = entry.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                    reading.counters = InterfaceCounters(bytesIn: UInt64(data.pointee.ifi_ibytes), bytesOut: UInt64(data.pointee.ifi_obytes))
                }
            default:
                break
            }
            byName[name] = reading
        }
        return Array(byName.values)
    }
}
