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

    /// Removes every registered body (tests).
    @MainActor public static func removeAll() { bodies.removeAll() }

    /// True when a body is registered for the page.
    public static func hasBody(for pageID: String) -> Bool { bodies[pageID] != nil }

    /// The registered body, if any.
    @MainActor static func body(for pageID: String) -> AnyView? { bodies[pageID]?() }
}
