import Foundation
import Testing
@testable import KeepAwakeFeature

/// In-memory preferences: nothing is ever written to ~/Library/Preferences.
final class MemoryDefaults: KeyValueReading {
    private var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}

final class Box<T>: @unchecked Sendable { var value: T; init(_ v: T) { value = v } }

@Suite struct KeepAwakeSettingsTests {
    func fresh() -> MemoryDefaults { MemoryDefaults() }

    @Test func defaultsWhenAbsent() {
        let s = KeepAwakeSettings(defaults: fresh())
        #expect(s.defaultDurationMinutes == 0)
        #expect(s.activityKeepsAwake)
    }

    @Test func readsTheMigratedKeysWithTheirOldNames() {
        let d = fresh()
        d.set(120, forKey: "defaultDurationMinutes")
        d.set(false, forKey: "notchKeepAwakeActivity")
        let s = KeepAwakeSettings(defaults: d)
        #expect(s.defaultDurationMinutes == 120)
        #expect(!s.activityKeepsAwake)
    }

    @Test func aNegativeDurationMeansNoLimit() {
        let d = fresh()
        d.set(-5, forKey: "defaultDurationMinutes")
        #expect(KeepAwakeSettings(defaults: d).defaultDurationMinutes == 0)
    }
}
