import IslandKit
import PortKit

/// The island's "Mixer" tab. The mixer, the output switcher and the device priority are the ported Vorssaint
/// services now (`PortKit/Bridge/Mixer.swift`): this target only keeps the tab id `audio` (the Home tile, the
/// command bar and the migrated switch all point at it) and hosts the ported panel in it. The registry starts and
/// stops the services through `PortFeatureBinding`, not through this type.
public enum AudioFeature {
    @MainActor public static func tab() -> IslandTab { PortMixer.tab() }
}
