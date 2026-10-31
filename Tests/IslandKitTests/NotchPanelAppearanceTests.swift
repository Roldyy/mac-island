import AppKit
import Testing
@testable import IslandKit

@MainActor
@Suite struct NotchPanelAppearanceTests {
    /// The island merges with the black notch, so it stays dark whatever the system appearance is.
    @Test func panelIsAlwaysDarkAqua() {
        let panel = NotchPanel()
        #expect(panel.appearance?.name == .darkAqua)
        #expect(panel.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    }
}
