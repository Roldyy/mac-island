import Testing
@testable import MonitorFeature

@Suite struct SamplingPolicyTests {
    @Test func visibleSamplesAtOneHertz() {
        #expect(SamplingCadence.interval(visible: true, alertsEnabled: false, background: 5) == 1)
        #expect(SamplingCadence.interval(visible: true, alertsEnabled: true, background: 5) == 1)
    }

    @Test func hiddenWithAlertsUsesTheBackgroundCadence() {
        #expect(SamplingCadence.interval(visible: false, alertsEnabled: true, background: 5) == 5)
        #expect(SamplingCadence.interval(visible: false, alertsEnabled: true, background: 7) == 7)
    }

    @Test func hiddenWithoutAlertsDoesNothing() {
        #expect(SamplingCadence.interval(visible: false, alertsEnabled: false, background: 5) == nil)
    }

    @Test func backgroundCadenceIsBounded() {
        #expect(SamplingCadence.interval(visible: false, alertsEnabled: true, background: 0.1) == 5)
        #expect(SamplingCadence.interval(visible: false, alertsEnabled: true, background: 600) == 10)
    }

    @Test func notificationPolicy() {
        #expect(NotificationPolicy.mode(hasBundle: false, status: .authorized, userEnabled: true) == .inIslandOnly)
        #expect(NotificationPolicy.mode(hasBundle: true, status: .notDetermined, userEnabled: true) == .inIslandOnly)
        #expect(NotificationPolicy.mode(hasBundle: true, status: .denied, userEnabled: true) == .inIslandOnly)
        #expect(NotificationPolicy.mode(hasBundle: true, status: .authorized, userEnabled: false) == .inIslandOnly)
        #expect(NotificationPolicy.mode(hasBundle: true, status: .authorized, userEnabled: true) == .system)
    }
}
