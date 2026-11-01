import SwiftUI
import Testing
@testable import ShellKit

@Suite(.serialized) @MainActor struct SettingsPageBodiesTests {
    @Test func nothingIsRegisteredByDefault() {
        SettingsPageBodies.removeAll()
        #expect(!SettingsPageBodies.hasBody(for: "scrollreverse"))
        #expect(SettingsPageBodies.body(for: "scrollreverse") == nil)
    }

    @Test func aRegisteredBodyIsFoundAndStopsTheComingSoonBadge() {
        SettingsPageBodies.removeAll()
        defer { SettingsPageBodies.removeAll() }
        let page = SettingsPage(id: "ported-test-page", title: "Test", symbol: "gear", section: .essentials,
                                summary: "Page de test.")
        #expect(page.isComingSoon)
        SettingsPageBodies.register(pageID: page.id) { AnyView(Text("corps")) }
        #expect(SettingsPageBodies.hasBody(for: page.id))
        #expect(SettingsPageBodies.body(for: page.id) != nil)
        #expect(!page.isComingSoon)
    }
}
