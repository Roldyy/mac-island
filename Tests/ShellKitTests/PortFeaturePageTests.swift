import AppKit
import Foundation
import IslandKit
import IslandTestSupport
import SwiftUI
import Testing
@testable import ShellKit

/// A ported feature's page: its switch and status card first, then the ported body.
@Suite(.serialized) @MainActor struct PortFeaturePageTests {
    @Test func aFeaturePageOpensWithTheFeatureCardAndStopsReadingComingSoon() {
        SettingsPageBodies.removeAll()
        defer { SettingsPageBodies.removeAll() }
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-test-marker-\(UUID().uuidString)"))
        let descriptor = FeatureDescriptor(id: "ported", title: "Fonction portée", summary: "Résumé.", systemImage: "link",
                                           category: .files, enabledByDefault: false)
        let registry = FeatureRegistry(descriptors: [descriptor], defaults: bench.defaults, crashMarker: marker,
                                       withdraw: { _ in })
        let page = SettingsPage(id: "ported-page", title: "Page", symbol: "gear", section: .files, summary: "Page.")
        #expect(page.isComingSoon)

        SettingsPageBodies.register(pageID: page.id, featureID: "ported", registry: registry, openPermission: { _ in }) {
            AnyView(Text("corps du portage").accessibilityIdentifier("ported-body"))
        }
        #expect(SettingsPageBodies.hasBody(for: page.id))
        #expect(!page.isComingSoon)

        let body = SettingsPageBodies.body(for: page.id)
        #expect(body != nil)
        let host = NSHostingView(rootView: body ?? AnyView(EmptyView()))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        host.layoutSubtreeIfNeeded()
        // The card (title, summary, toggle, badge) and the body both take room.
        #expect(host.fittingSize.height > 80, "rendered: \(host.fittingSize)")
    }
}
