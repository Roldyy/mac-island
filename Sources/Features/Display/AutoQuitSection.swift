import SwiftUI

/// Auto-quit of idle apps: switch, delay, dry-run list and the exclusion list.
struct AutoQuitSection: View {
    @Bindable var model: AutoQuitModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Quitter les apps inactives", isOn: $model.enabled)
                .toggleStyle(.switch)
                .font(.headline)
                .accessibilityLabel("Quitter automatiquement les apps sans fenêtre")
            if model.enabled {
                Stepper(value: $model.delayMinutes, in: 1...DisplaySettings.maxDelayMinutes, step: 5) {
                    Text("Après \(model.delayMinutes) min sans fenêtre")
                }
                .accessibilityLabel("Délai d'inactivité en minutes")
                Toggle("Simulation seulement (ne rien quitter)", isOn: $model.dryRun)
                    .accessibilityLabel("Mode simulation")
                PendingQuitList(model: model)
            }
            ExclusionList(model: model)
        }
    }
}
