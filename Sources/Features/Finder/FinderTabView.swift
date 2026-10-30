import SwiftUI

/// The tab: two toggles, permission lines, what is cut. Black island, no hover side effects,
/// never takes the keyboard.
struct FinderTabView: View {
    @Bindable var model: FinderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Couper / coller des fichiers (Cmd+X, Cmd+V)", isOn: $model.cutPasteEnabled)
                .accessibilityHint("Cmd+X marque les éléments, Cmd+V les déplace dans le dossier ouvert")
            Toggle("Coller une image comme fichier PNG", isOn: $model.pasteImageAsFile)
                .accessibilityHint("Cmd+V avec une image dans le presse-papiers crée un fichier dans le dossier ouvert")

            Divider().overlay(Color.white.opacity(0.15))

            statusRow(model.permissionLine, button: "Réglages Accessibilité", action: model.openAccessibilitySettings,
                      hint: "Ouvre Réglages Système, Confidentialité, Accessibilité")
            if model.accessibility && !model.inputMonitoring {
                statusRow("Autorisez aussi la surveillance de l'entrée", button: "Réglages Entrée",
                          action: model.openInputMonitoringSettings,
                          hint: "Ouvre Réglages Système, Confidentialité, Surveillance de l'entrée")
            }
            statusRow(model.automationLine, button: "Autoriser le Finder", action: model.requestAutomation,
                      hint: "Affiche la demande d'automatisation du Finder")

            HStack {
                Text(model.cutLine).accessibilityLabel(model.cutLine)
                if model.cutCount > 0 {
                    Button("Annuler la coupe", action: model.cancelCut)
                        .accessibilityHint("Oublie les éléments coupés sans rien déplacer")
                }
            }
            .font(.callout)

            if model.needsConfirmation {
                Button("Confirmer le déplacement", action: model.confirmLargeMove)
                    .accessibilityHint("Déplace tous les éléments coupés malgré leur nombre élevé")
            }
            Text(model.outcomeLine)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(2)
                .accessibilityLabel(model.outcomeLine)
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .task {
            model.start()
            // While the tab is visible, follow permission changes and cut expiry.
            while !Task.isCancelled {
                model.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func statusRow(_ text: String, button: String, action: @escaping () -> Void, hint: String) -> some View {
        HStack {
            Text(text).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
                .accessibilityLabel(text)
            Spacer(minLength: 8)
            Button(button, action: action).font(.caption).accessibilityHint(hint)
        }
    }
}
