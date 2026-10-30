import Foundation
import Testing
@testable import KeepAwakeFeature

@Suite struct KeepAwakeSettingsTests {
    func fresh() -> UserDefaults {
        let name = "keepawake-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func defaultsWhenAbsent() {
        let s = KeepAwakeSettings(defaults: fresh())
        #expect(!s.mouseJiggleEnabled)
        #expect(s.mouseJiggleIntervalMinutes == 1)
        #expect(s.defaultDurationMinutes == 0)
        #expect(s.activityKeepsAwake)
        #expect(!s.preventDisplaySleep)
        #expect(s.clamshellPreferred == false)
    }

    @Test func readsTheMigratedKeysWithTheirOldNames() {
        let d = fresh()
        d.set(true, forKey: "keepAwakeMouseJiggleEnabled")
        d.set(5, forKey: "keepAwakeMouseJiggleIntervalMinutes")
        d.set(120, forKey: "defaultDurationMinutes")
        d.set(false, forKey: "notchKeepAwakeActivity")
        d.set(true, forKey: "clamshellPreferred")
        let s = KeepAwakeSettings(defaults: d)
        #expect(s.mouseJiggleEnabled)
        #expect(s.mouseJiggleIntervalMinutes == 5)
        #expect(s.defaultDurationMinutes == 120)
        #expect(!s.activityKeepsAwake)
        #expect(s.clamshellPreferred)
    }

    @Test func intervalBelowOneIsClamped() {
        let d = fresh()
        d.set(0, forKey: "keepAwakeMouseJiggleIntervalMinutes")
        #expect(KeepAwakeSettings(defaults: d).mouseJiggleIntervalMinutes == 1)
    }
}
