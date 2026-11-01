import IslandKit
import PortKit

/// The island's "Dock" tab. Dock Preview and the Dock clicks are the ported Vorssaint services now
/// (`PortKit/Bridge/Dock.swift`): this target only keeps the tab id `dock` (the Home tile, the Settings pages and the
/// migrated switch all point at it) and hosts the ported cards in it. The registry starts and stops the services
/// through `PortFeatureBinding`, not through this type.
public enum DockFeature {
    @MainActor public static func tab() -> IslandTab { PortDock.tab() }
}
