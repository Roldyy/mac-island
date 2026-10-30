import Testing
@testable import SettingsKit

@Suite struct KeyMapTests {
    @Test func keepAwakeDurationIsCarried() {
        #expect(VorssaintKeyMap.verdict(for: "defaultDurationMinutes") == .carry)
    }

    @Test func clamshellStaysUnmappedBecauseItNeedsRoot() {
        #expect(VorssaintKeyMap.verdict(for: "clamshellPreferred") == .unknown)
    }
}
