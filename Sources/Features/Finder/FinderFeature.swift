import IslandKit
import SwiftUI

public enum FinderFeature {
    /// Created on first use only, so building the tab list touches nothing (no tap, no permission).
    @MainActor static let shared = FinderModel()

    /// What the ported Finder engine (PortKit: cut and paste, rename shortcut) reports to the tab.
    public struct EngineStatus: Equatable, Sendable {
        public var running: Bool
        public var cutCount: Int
        public init(running: Bool, cutCount: Int) {
            self.running = running
            self.cutCount = cutCount
        }
    }

    /// Set by the app once the ported engine owns the key taps. While it is set, the tab only shows and forwards:
    /// it installs no tap of its own (two taps on one key would move every file twice), reads this status, and
    /// asks `engineSync` to re-read the preferences after one of its two switches changed.
    @MainActor public static var engineStatus: (() -> EngineStatus)?
    @MainActor public static var engineSync: (() -> Void)?
    /// The tab's "Annuler la coupe" while the ported engine holds the cut items.
    @MainActor public static var engineCancelCut: (() -> Void)?

    @MainActor public static func tab() -> IslandTab {
        IslandTab(id: "finder", title: "Finder", systemImage: "folder") {
            AnyView(FinderTabView(model: shared))
        }
    }

    /// Install the key tap if the toggles and permissions allow it. Idempotent. Never prompts.
    @MainActor public static func start() { shared.start() }

    /// Remove the key tap and forget any pending cut. Idempotent.
    /// Cleaning mode is not here any more: it is the ported feature (`PortCleaningMode` in PortKit).
    @MainActor public static func stop() { shared.stop() }
}
