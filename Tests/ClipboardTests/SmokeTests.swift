import Testing
@testable import ClipboardFeature

@Suite struct ClipboardSmokeTests {
    @Test @MainActor func tabHasStableIdentity() {
        #expect(ClipboardFeature.tab().id == "clipboard")
    }
}
