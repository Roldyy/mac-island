import Foundation
import Observation

/// The scanner's few preferences, stored under `ipscanner.*`. Nothing about a scan result is ever stored.
@MainActor @Observable
public final class IPScannerSettings {
    enum Keys {
        static let concurrency = "ipscanner.concurrency"
        static let timeoutMs = "ipscanner.timeoutMs"
        static let resolveNames = "ipscanner.resolveNames"
        static let bonjour = "ipscanner.bonjour"
        static let ports = "ipscanner.ports"
    }

    // An observer that corrects its own property must stop once the value is already right: under @Observable the
    // assignment goes through the generated setter and fires the observer again.
    public var concurrency: Int {
        didSet {
            let valid = Self.clamp(concurrency, ScanConfiguration.concurrencyRange)
            if valid != concurrency { concurrency = valid; return }
            defaults.set(valid, forKey: Keys.concurrency)
        }
    }
    public var timeoutMs: Int {
        didSet {
            let valid = Self.clamp(timeoutMs, ScanConfiguration.timeoutRangeMs)
            if valid != timeoutMs { timeoutMs = valid; return }
            defaults.set(valid, forKey: Keys.timeoutMs)
        }
    }
    public var resolveNames: Bool { didSet { defaults.set(resolveNames, forKey: Keys.resolveNames) } }
    public var useBonjour: Bool { didSet { defaults.set(useBonjour, forKey: Keys.bonjour) } }
    /// Ports checked for the port scan, always a subset of the presets.
    public var ports: Set<UInt16> {
        didSet {
            let clean = Set(PortPreset.sanitized(ports))
            if clean != ports { ports = clean; return }
            defaults.set(PortPreset.sanitized(clean).map { Int($0) }, forKey: Keys.ports)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        concurrency = Self.clamp((defaults.object(forKey: Keys.concurrency) as? Int) ?? 64, ScanConfiguration.concurrencyRange)
        timeoutMs = Self.clamp((defaults.object(forKey: Keys.timeoutMs) as? Int) ?? 800, ScanConfiguration.timeoutRangeMs)
        resolveNames = (defaults.object(forKey: Keys.resolveNames) as? Bool) ?? true
        useBonjour = (defaults.object(forKey: Keys.bonjour) as? Bool) ?? true
        if let stored = defaults.array(forKey: Keys.ports) as? [Int] {
            ports = Set(PortPreset.sanitized(stored.compactMap(UInt16.init(exactly:))))
        } else {
            ports = PortPreset.defaultPorts
        }
    }

    public var scanConfiguration: ScanConfiguration {
        var configuration = ScanConfiguration()
        configuration.concurrency = concurrency
        configuration.timeout = .milliseconds(timeoutMs)
        configuration.resolveNames = resolveNames
        configuration.useBonjour = useBonjour
        return configuration.clamped
    }

    public func resetToDefaults() {
        concurrency = 64
        timeoutMs = 800
        resolveNames = true
        useBonjour = true
        ports = PortPreset.defaultPorts
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int { min(max(value, range.lowerBound), range.upperBound) }
}
