import Testing
@testable import AudioFeature

@Suite struct AudioSmokeTests {
    /// The Home tile, the command bar and the migrated switch all reach the mixer through the tab id `audio`.
    @Test @MainActor func tabHasStableIdentity() {
        let tab = AudioFeature.tab()
        #expect(tab.id == "audio")
        #expect(tab.title == "Mixer")
        #expect(tab.systemImage == "slider.vertical.3")
    }
}
