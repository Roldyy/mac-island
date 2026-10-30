import Testing
@testable import DockFeature

@Suite struct PermissionStatusTests {
    @Test func linesNameWhatIsMissing() {
        #expect(PermissionLines.accessibility(granted: true).contains("granted"))
        #expect(PermissionLines.accessibility(granted: false).contains("Accessibility"))
        #expect(PermissionLines.screenRecording(granted: true).contains("granted"))
        #expect(PermissionLines.screenRecording(granted: false).contains("Screen Recording"))
    }
}
