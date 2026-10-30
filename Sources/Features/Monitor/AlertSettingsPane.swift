import SwiftUI

/// Alert toggles, thresholds and durations. Steppers only: nothing here takes the keyboard.
struct AlertSettingsPane: View {
    @Bindable var model: MonitorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Alertes CPU et mémoire", isOn: $model.alertsEnabled)
                .accessibilityHint("Surveille aussi en arrière-plan, toutes les quelques secondes")
            Group {
                Stepper(value: $model.cpuThreshold, in: 50...100, step: 5) {
                    Text("Seuil processeur : \(Int(model.cpuThreshold)) %")
                }
                Stepper(value: $model.memoryThreshold, in: 50...100, step: 5) {
                    Text("Seuil mémoire : \(Int(model.memoryThreshold)) %")
                }
                Stepper(value: $model.sustainedSeconds, in: 10...300, step: 10) {
                    Text("Durée avant alerte : \(model.sustainedSeconds) s")
                }
                Stepper(value: $model.cooldownMinutes, in: 1...120, step: 1) {
                    Text("Délai entre deux alertes : \(model.cooldownMinutes) min")
                }
            }
            .disabled(!model.alertsEnabled)
            notificationControls
        }
        .font(.caption)
        .foregroundStyle(.white)
        .controlSize(.small)
        .task { await model.refreshNotificationStatus() }
    }

    @ViewBuilder private var notificationControls: some View {
        if !model.hasBundle {
            Text("Application non empaquetée : les alertes s'affichent dans l'île uniquement.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
        } else {
            switch model.notificationStatus {
            case .authorized:
                Toggle("Notifications système", isOn: $model.systemNotificationsEnabled)
            case .notDetermined:
                Button("Autoriser les notifications système") {
                    Task { await model.requestNotificationAuthorization() }
                }
                .accessibilityHint("Affiche la demande d'autorisation de macOS")
            case .denied:
                Text("Notifications refusées : à réactiver dans Réglages Système.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            case .unavailable:
                Text("Notifications indisponibles : les alertes s'affichent dans l'île.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }
}
