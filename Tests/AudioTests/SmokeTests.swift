import Testing
@testable import AudioFeature

@Suite struct AudioSmokeTests {
    @Test @MainActor func tabHasStableIdentity() {
        #expect(AudioFeature.tab().id == "audio")
    }
}
