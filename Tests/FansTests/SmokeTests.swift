import Testing
@testable import FansFeature

@Suite struct FansSmokeTests {
    @Test @MainActor func tabHasStableIdentity() {
        let tab = FansFeature.tab()
        #expect(tab.id == "fans")
        #expect(tab.title == "Ventilos")
        #expect(tab.systemImage == "fan")
    }

    /// The shell's indicator reads the shared model; nothing is manual at launch.
    @Test @MainActor func manualIndicatorFollowsTheSharedModel() {
        #expect(!FansFeature.isManualActive)
        #expect(FansFeature.isManualActive == FansFeature.shared.manualActive)
    }

    /// The warning must not promise a restore on closing the island any more.
    @Test func warningNamesTheWaysOutOfManualMode() {
        let text = ManualControlSection.warning
        #expect(text.contains("Retour automatique"))
        #expect(text.contains("quitte"))
        #expect(text.contains("95 °C"))
        #expect(!text.contains("onglet"))
    }
}
