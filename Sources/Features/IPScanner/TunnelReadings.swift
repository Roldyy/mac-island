import Darwin
import Foundation
import IslandKit

/// The interfaces `SamplingMath.vpnActive` needs (name, up, has an IPv4 address), read with `getifaddrs`. No packet,
/// no permission, no counters.
public enum TunnelReadings {
    public static func current() -> [InterfaceReading] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var byName: [String: InterfaceReading] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let name = String(cString: entry.pointee.ifa_name)
            let flags = Int32(entry.pointee.ifa_flags)
            let up = flags & IFF_UP != 0 && flags & IFF_RUNNING != 0
            let isIPv4 = entry.pointee.ifa_addr?.pointee.sa_family == sa_family_t(AF_INET)
            var reading = byName[name] ?? InterfaceReading(name: name, isUp: up, hasIPv4: false, counters: nil)
            reading.hasIPv4 = reading.hasIPv4 || isIPv4
            byName[name] = reading
        }
        return Array(byName.values)
    }
}
