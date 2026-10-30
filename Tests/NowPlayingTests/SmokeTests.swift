import Testing
@testable import NowPlayingFeature

@Suite struct NowPlayingSmokeTests {
    @Test @MainActor func tabHasStableIdentity() {
        #expect(NowPlayingFeature.tab().id == "nowplaying")
    }
}
