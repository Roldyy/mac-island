import Foundation
import IOKit
import ShellKit

/// Battery wear, read from the smart battery's registry entry (public IOKit, no permission).
struct BatteryHealth: Equatable, Sendable {
    var percent: Int
    var cycles: Int?

    /// Current full-charge capacity over the design capacity, capped at 100. Nil when either is unknown.
    static func make(rawMaxCapacity: Int?, designCapacity: Int?, cycles: Int?) -> BatteryHealth? {
        guard let rawMaxCapacity, let designCapacity, designCapacity > 0, rawMaxCapacity > 0 else { return nil }
        let percent = min(100, Int((Double(rawMaxCapacity) / Double(designCapacity) * 100).rounded()))
        return BatteryHealth(percent: percent, cycles: cycles)
    }

    /// Reads `AppleSmartBattery`: `AppleRawMaxCapacity` and `DesignCapacity` (mAh) and `CycleCount`.
    /// Nil on a Mac with no such entry or where a key is missing (UNKNOWN on every model: only checked by reading it).
    static func current() -> BatteryHealth? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        func int(_ key: String) -> Int? {
            (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue
        }
        return make(rawMaxCapacity: int("AppleRawMaxCapacity"), designCapacity: int("DesignCapacity"), cycles: int("CycleCount"))
    }
}

/// The lines of the "Batterie" tab, in French. Pure: a reading and an optional health in, strings out.
struct BatteryDisplay: Equatable, Sendable {
    let reading: BatteryReading
    let health: BatteryHealth?

    var percentText: String { "\(reading.percent) %" }

    var stateText: String {
        if reading.isCharging { return "En charge" }
        if reading.isPluggedIn { return reading.percent >= 100 ? "Chargée" : "Sur secteur" }
        return "Sur batterie"
    }

    var remainingText: String? {
        guard let minutes = reading.minutes else { return nil }
        let h = minutes / 60, m = minutes % 60
        let span = h > 0 ? "\(h) h \(m) min" : "\(m) min"
        if reading.isCharging { return "Pleine dans \(span)" }
        return reading.isPluggedIn ? nil : "\(span) restantes"
    }

    var healthText: String? {
        guard let health else { return nil }
        var text = "Santé \(health.percent) %"
        if let cycles = health.cycles { text += " · \(cycles) \(cycles == 1 ? "cycle" : "cycles")" }
        return text
    }
}
