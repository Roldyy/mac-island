import IslandKit

/// What the "Autoriser" button of a feature card does. One place for the three cards (feature page, features hub,
/// declarative page): Automation asks the feature's target app first (the pane alone never makes macOS list the
/// app), every other permission goes to the host's `openPermission`.
@MainActor
enum PermissionClick {
    static func perform(_ permission: FeaturePermission, featureID: String, registry: FeatureRegistry,
                        openPermission: @MainActor (FeaturePermission) -> Void) {
        registry.noteOpened(permission)
        guard permission == .automation else {
            openPermission(permission)
            return
        }
        // Automation is not in the monitor's snapshot: the card re-reads the registry once macOS has answered.
        UserPermissionRequest.requestAutomation(featureID: featureID) { [weak registry] _ in
            registry?.refreshCapabilities()
        }
    }
}
