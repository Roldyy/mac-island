import Foundation

/// Test-only helpers. Defaults suites live in the temp directory so no test leaves a plist in
/// ~/Library/Preferences.
public enum TestDefaults {
    /// `fenced: true` returns a `FencedDefaults`: `register(defaults:)` stays inside it.
    public static func make(_ name: String = UUID().uuidString, fenced: Bool = false)
        -> (defaults: UserDefaults, cleanup: () -> Void) {
        let path = NSTemporaryDirectory() + "mis-test-\(name)"
        let defaults: UserDefaults = fenced ? FencedDefaults(suiteName: path)! : UserDefaults(suiteName: path)!
        return (defaults, { defaults.removePersistentDomain(forName: path); try? FileManager.default.removeItem(atPath: path + ".plist") })
    }
}

/// A defaults suite whose registered defaults never leave it.
///
/// `UserDefaults.register(defaults:)` fills ONE process-wide registration domain, whichever instance it is called
/// on, and nothing can empty it again (`removeVolatileDomain(forName: registrationDomain)` is a no-op). After a
/// test ran PortKit's `Defaults.register`, every other suite in the process read upstream's registered values
/// (`clipboardHistoryEnabled == false`, `notchIdleContent == "music"`) as if stored, and tests passed or failed by
/// scheduling order. This subclass keeps the registration in its own dictionary and answers reads from
/// stored value, then its own registrations, so the code under test sees the real layering and nothing leaks.
public final class FencedDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var registered: [String: Any] = [:]

    public override init?(suiteName suitename: String?) { super.init(suiteName: suitename) }

    public override func register(defaults registrationDictionary: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        registered.merge(registrationDictionary) { _, new in new }
    }

    public override func object(forKey defaultName: String) -> Any? {
        if let stored = super.object(forKey: defaultName) { return stored }
        lock.lock(); defer { lock.unlock() }
        return registered[defaultName]
    }

    public override func bool(forKey defaultName: String) -> Bool {
        switch object(forKey: defaultName) {
        case let n as NSNumber: return n.boolValue
        case let s as String: return ["yes", "true", "1"].contains(s.lowercased())
        default: return false
        }
    }
    public override func integer(forKey defaultName: String) -> Int { (object(forKey: defaultName) as? NSNumber)?.intValue ?? 0 }
    public override func double(forKey defaultName: String) -> Double { (object(forKey: defaultName) as? NSNumber)?.doubleValue ?? 0 }
    public override func float(forKey defaultName: String) -> Float { (object(forKey: defaultName) as? NSNumber)?.floatValue ?? 0 }
    public override func string(forKey defaultName: String) -> String? { object(forKey: defaultName) as? String }
    public override func array(forKey defaultName: String) -> [Any]? { object(forKey: defaultName) as? [Any] }
    public override func stringArray(forKey defaultName: String) -> [String]? { object(forKey: defaultName) as? [String] }
    public override func dictionary(forKey defaultName: String) -> [String: Any]? { object(forKey: defaultName) as? [String: Any] }
    public override func data(forKey defaultName: String) -> Data? { object(forKey: defaultName) as? Data }

    public override func dictionaryRepresentation() -> [String: Any] {
        lock.lock(); let mine = registered; lock.unlock()
        return mine.merging(super.dictionaryRepresentation()) { _, stored in stored }
    }
}

/// How much slower than an idle machine this one is right now, for tests that must keep a time budget.
///
/// A wall-clock budget fails when other builds or tests load the machine, not when the code is wrong. The budget
/// is therefore multiplied by `LoadScale.measure()`: the time a fixed CPU loop takes, over the time it takes on an
/// idle machine. Measure before AND after the timed work and use the larger factor, so load that arrives or leaves
/// mid-test is counted. Never below 1: a fast machine does not tighten a budget.
public enum LoadScale {
    /// Seconds the calibration loop takes on an idle machine (debug build).
    static let idleSeconds = 0.0076
    private nonisolated(unsafe) static var sink = 0.0

    @inline(never)
    private static func spin() {
        var x = 0.0
        for i in 0..<100_000 { x += Double(i).squareRoot() }
        sink = x
    }

    /// The factor (>= 1), from the fastest of a few runs: the least disturbed one says what the machine can do.
    public static func measure(runs: Int = 5) -> Double {
        let clock = ContinuousClock()
        var best = Double.infinity
        for _ in 0..<max(1, runs) {
            let start = clock.now
            spin()
            let d = clock.now - start
            best = min(best, Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18)
        }
        return max(1, best / idleSeconds)
    }
}
