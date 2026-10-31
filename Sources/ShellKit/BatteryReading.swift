import Foundation
import IOKit.ps
import IslandKit
import IslandUI

/// One look at the internal battery. Plain data, so formatting is testable without hardware.
public struct BatteryReading: Equatable, Sendable {
    public var percent: Int
    /// The Mac is on the charger (charging or already full).
    public var isPluggedIn: Bool
    public var isCharging: Bool
    /// Minutes to empty on battery or to full on the charger; nil while the system has no estimate.
    public var minutes: Int?

    public init(percent: Int, isPluggedIn: Bool, isCharging: Bool, minutes: Int? = nil) {
        self.percent = min(max(percent, 0), 100)
        self.isPluggedIn = isPluggedIn
        self.isCharging = isCharging
        self.minutes = minutes.flatMap { $0 > 0 ? $0 : nil }
    }

    public static let indicatorID = "battery"

    /// Below this, off the charger, the indicator pins and pulses.
    public static let lowThreshold = 20
    public static let criticalThreshold = 10

    public var isLow: Bool { !isPluggedIn && percent < Self.lowThreshold }

    public var status: IslandStatus {
        if isPluggedIn { return .success }
        if percent < Self.criticalThreshold { return .danger }
        if percent < Self.lowThreshold { return .warning }
        return .neutral
    }

    /// "82%": the wing is too narrow for a space; VoiceOver gets the full sentence in `spoken`.
    public var text: String { "\(percent)%" }

    /// Level-matched battery symbol; the charger gets the bolt (the only bolt variant is the full one).
    public var symbol: String {
        if isPluggedIn { return "battery.100percent.bolt" }
        switch percent {
        case ..<10: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    /// Spoken sentence: level, charger state, remaining time when the system knows it.
    public var spoken: String {
        var parts = ["Batterie \(percent) %"]
        if isCharging { parts.append("en charge") } else if isPluggedIn { parts.append("sur secteur") }
        if let minutes {
            let h = minutes / 60, m = minutes % 60
            let span = h > 0 ? "\(h) h \(m) min" : "\(m) min"
            parts.append(isPluggedIn ? "pleine dans \(span)" : "\(span) restantes")
        }
        if isLow { parts.append("niveau bas") }
        return parts.joined(separator: ", ")
    }

    /// The indicator the closed island shows. Low battery is urgent: it pins and pulses once.
    public var indicator: AmbientIndicator {
        AmbientIndicator(
            id: Self.indicatorID, channel: AmbientChannel.battery, symbol: symbol, text: text,
            status: status, priority: isLow ? .alert : .ambient, isUrgent: isLow, wing: .trailing, label: spoken)
    }
}

extension BatteryReading {
    /// Reads the internal battery through IOKit's power-source API: a handful of dictionary lookups, no
    /// permission, no polling. Nil on a Mac without an internal battery.
    public static func current() -> BatteryReading? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  (description[kIOPSIsPresentKey] as? Bool) ?? true,
                  let capacity = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let plugged = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let charging = (description[kIOPSIsChargingKey] as? Bool) ?? false
            let key = plugged ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            return BatteryReading(
                percent: Int((Double(capacity) / Double(maximum) * 100).rounded()),
                isPluggedIn: plugged, isCharging: charging, minutes: description[key] as? Int)
        }
        return nil
    }
}
