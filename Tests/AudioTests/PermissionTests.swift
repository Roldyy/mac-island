import Testing
@testable import AudioFeature

@Suite struct PermissionTests {
    @Test func withoutUsageDescriptionNeedsBundledApp() {
        #expect(AudioPermission.resolve(hasUsageDescription: false, probe: nil) == .needsBundledApp)
        #expect(AudioPermission.resolve(hasUsageDescription: false, probe: 0) == .needsBundledApp)
    }

    @Test func bundledButNeverProbedIsUnknown() {
        #expect(AudioPermission.resolve(hasUsageDescription: true, probe: nil) == .notChecked)
    }

    @Test func probeSuccessIsReadyAndFailureCarriesStatus() {
        #expect(AudioPermission.resolve(hasUsageDescription: true, probe: 0) == .ready)
        #expect(AudioPermission.resolve(hasUsageDescription: true, probe: -50) == .failed(-50))
    }

    @Test func statusLinesMentionTheBundledApp() {
        #expect(AudioPermission.needsBundledApp.line.contains("app"))
        #expect(AudioPermission.failed(-50).line.contains("-50"))
    }

    @Test func buttonOnlyWhenItCanDoSomething() {
        #expect(AudioPermission.needsBundledApp.canRequest == false)
        #expect(AudioPermission.notChecked.canRequest)
        #expect(AudioPermission.failed(1).canRequest)
        #expect(AudioPermission.ready.canRequest == false)
    }
}
