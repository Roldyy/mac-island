import IslandKit
import IslandUI
import SwiftUI

/// Extension point for page bodies that live outside ShellKit (the ported Vorssaint pages). A lane registers
/// one body per page id at launch; the page scaffold then shows it under the page's own rows, and the page
/// stops reading "Bientôt". Nothing is registered by default, so every page looks exactly as before.
///
/// Registration and reads happen on the main thread only (launch and view bodies).
public enum SettingsPageBodies {
    private nonisolated(unsafe) static var bodies: [String: @MainActor () -> AnyView] = [:]

    /// Registers (or replaces) the body of one page.
    @MainActor public static func register(pageID: String, _ body: @escaping @MainActor () -> AnyView) {
        bodies[pageID] = body
    }

    /// Registers a body UNDER the one already registered for the page (when there is one): a page two lanes (or a lane and
    /// the app) both draw shows both, in registration order, and the last registration never erases the first.
    @MainActor public static func registerComposed(pageID: String, _ body: @escaping @MainActor () -> AnyView) {
        guard let earlier = bodies[pageID] else { register(pageID: pageID, body); return }
        register(pageID: pageID) {
            AnyView(VStack(alignment: .leading, spacing: IslandSpacing.l) {
                earlier()
                body()
            })
        }
    }

    /// Registers the body of a page that belongs to one registry feature (a ported feature's page): the page
    /// opens with that feature's switch and status card, the same card the declarative pages show, then the body.
    /// The catalog row of such a page has no `featureID`, and the catalog is not touched for it.
    @MainActor public static func register(pageID: String, featureID: String, registry: FeatureRegistry,
                                           openPermission: @escaping @MainActor (FeaturePermission) -> Void,
                                           _ body: @escaping @MainActor () -> AnyView) {
        // Composed, not replaced: a page a bound feature shares with another lane keeps the other body too.
        registerComposed(pageID: pageID) {
            AnyView(VStack(alignment: .leading, spacing: IslandSpacing.l) {
                FeatureStatusCard(registry: registry, featureID: featureID, openPermission: openPermission)
                body()
            })
        }
    }

    /// Removes every registered body (tests).
    @MainActor public static func removeAll() { bodies.removeAll() }

    /// True when a body is registered for the page.
    public static func hasBody(for pageID: String) -> Bool { bodies[pageID] != nil }

    /// The registered body, if any.
    @MainActor static func body(for pageID: String) -> AnyView? { bodies[pageID]?() }
}
