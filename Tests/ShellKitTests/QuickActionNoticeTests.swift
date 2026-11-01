import Testing
@testable import ShellKit

@Suite struct QuickActionNoticeTests {
    @Test func pastePlainNoticeNamesBothPermissions() {
        let text = QuickActionNotice.pastePlainNeedsAccess
        #expect(text == "Autorisation requise : Surveillance de l'entrée / Accessibilité")
        #expect(text.hasPrefix("Autorisation requise"))
        #expect(text.contains("Accessibilité") && text.contains("Surveillance de l'entrée"))
    }
}
