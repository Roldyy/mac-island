import IslandKit
import Foundation

/// How memory usage is computed for the gauge and the alert. The migrated key holds `used`;
/// no other value is known, so anything else reads as `used`.
enum MemoryMetric: String {
    case used
}

/// Reads and writes the monitor keys in the app's defaults suite.
///
/// Migrated keys (names kept): `monitorAlertCPUThreshold` (percent), `monitorAlertCooldownMinutes`,
/// `monitorIntervalSeconds`, `monitorMemoryMetric`. New keys (the old app had no equivalent):
/// `monitorAlertsEnabled`, `monitorAlertMemoryThreshold`, `monitorAlertSustainedSeconds`,
/// `monitorSystemNotificationsEnabled`.
struct MonitorSettings {
    static let suiteName = "be.roldy.macisland"

    static let cpuThresholdKey = "monitorAlertCPUThreshold"
    static let cooldownKey = "monitorAlertCooldownMinutes"
    static let intervalKey = "monitorIntervalSeconds"
    static let memoryMetricKey = "monitorMemoryMetric"
    static let alertsEnabledKey = "monitorAlertsEnabled"
    static let memoryThresholdKey = "monitorAlertMemoryThreshold"
    static let sustainedKey = "monitorAlertSustainedSeconds"
    static let systemNotificationsKey = "monitorSystemNotificationsEnabled"

    static let defaultThreshold = 90.0
    static let defaultSustainedSeconds = 30
    static let defaultCooldownMinutes = 15
    static let defaultIntervalSeconds = 5

    let defaults: UserDefaults

    init(defaults: UserDefaults = AppDefaults.make() ?? .standard) {
        self.defaults = defaults
    }

    private func number(_ key: String) -> Double? { (defaults.object(forKey: key) as? NSNumber)?.doubleValue }

    private func clamped(_ key: String, default fallback: Double, _ range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, number(key) ?? fallback))
    }

    /// Off until the user turns it on: nothing samples in the background by default.
    var alertsEnabled: Bool { (defaults.object(forKey: Self.alertsEnabledKey) as? Bool) ?? false }
    var cpuThreshold: Double { clamped(Self.cpuThresholdKey, default: Self.defaultThreshold, 1...100) }
    var memoryThreshold: Double { clamped(Self.memoryThresholdKey, default: Self.defaultThreshold, 1...100) }
    var sustainedSeconds: Int {
        Int(clamped(Self.sustainedKey, default: Double(Self.defaultSustainedSeconds), 0...3600))
    }
    var cooldownMinutes: Int {
        Int(clamped(Self.cooldownKey, default: Double(Self.defaultCooldownMinutes), 1...1440))
    }
    /// Background cadence while alerts are on and the island is closed: 5...10 s.
    var intervalSeconds: Int {
        Int(clamped(Self.intervalKey, default: Double(Self.defaultIntervalSeconds), 5...10))
    }
    var memoryMetric: MemoryMetric {
        defaults.string(forKey: Self.memoryMetricKey).flatMap(MemoryMetric.init(rawValue:)) ?? .used
    }
    var systemNotificationsEnabled: Bool {
        (defaults.object(forKey: Self.systemNotificationsKey) as? Bool) ?? false
    }

    func rule(threshold: Double, sustainedSeconds: Int, cooldownMinutes: Int) -> AlertRule {
        AlertRule(threshold: threshold, sustained: TimeInterval(sustainedSeconds),
                  cooldown: TimeInterval(cooldownMinutes) * 60, clearMargin: AlertRule.defaultClearMargin)
    }
    var cpuRule: AlertRule {
        rule(threshold: cpuThreshold, sustainedSeconds: sustainedSeconds, cooldownMinutes: cooldownMinutes)
    }
    var memoryRule: AlertRule {
        rule(threshold: memoryThreshold, sustainedSeconds: sustainedSeconds, cooldownMinutes: cooldownMinutes)
    }

    func setAlertsEnabled(_ v: Bool) { defaults.set(v, forKey: Self.alertsEnabledKey) }
    func setCPUThreshold(_ v: Double) { defaults.set(v, forKey: Self.cpuThresholdKey) }
    func setMemoryThreshold(_ v: Double) { defaults.set(v, forKey: Self.memoryThresholdKey) }
    func setSustainedSeconds(_ v: Int) { defaults.set(v, forKey: Self.sustainedKey) }
    func setCooldownMinutes(_ v: Int) { defaults.set(v, forKey: Self.cooldownKey) }
    func setSystemNotificationsEnabled(_ v: Bool) { defaults.set(v, forKey: Self.systemNotificationsKey) }
}
