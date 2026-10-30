import Foundation
import Testing
@testable import MonitorFeature

@Suite struct MonitorSettingsTests {
    private func fresh() -> (TempDefaults, MonitorSettings) {
        let t = TempDefaults()
        return (t, MonitorSettings(defaults: t.defaults))
    }

    @Test func defaultsWhenNothingMigrated() {
        let (_, s) = fresh()
        #expect(s.alertsEnabled == false)
        #expect(s.cpuThreshold == 90)
        #expect(s.memoryThreshold == 90)
        #expect(s.sustainedSeconds == 30)
        #expect(s.cooldownMinutes == 15)
        #expect(s.intervalSeconds == 5)
        #expect(s.systemNotificationsEnabled == false)
    }

    @Test func readsTheMigratedKeysUnderTheirOldNames() {
        let (t, s) = fresh()
        t.defaults.set(75, forKey: "monitorAlertCPUThreshold")
        t.defaults.set(20, forKey: "monitorAlertCooldownMinutes")
        t.defaults.set(8, forKey: "monitorIntervalSeconds")
        t.defaults.set("used", forKey: "monitorMemoryMetric")
        #expect(s.cpuThreshold == 75)
        #expect(s.cooldownMinutes == 20)
        #expect(s.intervalSeconds == 8)
        #expect(s.memoryMetric == .used)
    }

    @Test func clampsAbsurdValues() {
        let (t, s) = fresh()
        t.defaults.set(5000, forKey: "monitorAlertCPUThreshold")
        t.defaults.set(-3, forKey: "monitorAlertCooldownMinutes")
        t.defaults.set(1, forKey: "monitorIntervalSeconds")
        #expect(s.cpuThreshold == 100)
        #expect(s.cooldownMinutes == 1)
        #expect(s.intervalSeconds == 5)
        t.defaults.set(3600, forKey: "monitorIntervalSeconds")
        #expect(s.intervalSeconds == 10)
    }

    @Test func wrongTypesFallBackToDefaults() {
        let (t, s) = fresh()
        t.defaults.set("ninety", forKey: "monitorAlertCPUThreshold")
        t.defaults.set("yes please", forKey: "monitorAlertsEnabled")
        #expect(s.cpuThreshold == 90)
        #expect(s.alertsEnabled == false)
    }

    @Test func unknownMetricValueFallsBackToUsed() {
        let (t, s) = fresh()
        t.defaults.set("something-new", forKey: "monitorMemoryMetric")
        #expect(s.memoryMetric == .used)
    }

    @Test func writesRoundTrip() {
        let (_, s) = fresh()
        s.setAlertsEnabled(true)
        s.setMemoryThreshold(80)
        s.setSustainedSeconds(60)
        s.setCPUThreshold(70)
        s.setCooldownMinutes(5)
        s.setSystemNotificationsEnabled(true)
        #expect(s.alertsEnabled)
        #expect(s.memoryThreshold == 80)
        #expect(s.sustainedSeconds == 60)
        #expect(s.cpuThreshold == 70)
        #expect(s.cooldownMinutes == 5)
        #expect(s.systemNotificationsEnabled)
    }

    @Test func rulesAreBuiltInSeconds() {
        let (_, s) = fresh()
        s.setSustainedSeconds(45)
        s.setCooldownMinutes(2)
        #expect(s.cpuRule == AlertRule(threshold: 90, sustained: 45, cooldown: 120, clearMargin: 5))
    }
}
