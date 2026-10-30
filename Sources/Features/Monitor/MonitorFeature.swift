import IslandKit
import SwiftUI

public enum MonitorFeature {
    /// Created on first use, so building the tab list samples nothing and touches nothing.
    @MainActor static let shared = MonitorModel()

    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "monitor", title: "Moniteur", systemImage: "gauge.with.dots.needle.bottom.50percent") {
            AnyView(MonitorView(model: shared))
        }
    }

    /// Start background alert sampling if the user enabled alerts. Idempotent.
    @MainActor public static func start() { shared.start() }

    /// Stop every sampling loop. Idempotent.
    @MainActor public static func stop() { shared.stop() }

    /// The alert currently active, for the shell to show in the wings. Observable: read it inside
    /// `withObservationTracking` or a SwiftUI body.
    @MainActor public static var currentAlert: AlertNotice? { shared.currentAlert }
}
