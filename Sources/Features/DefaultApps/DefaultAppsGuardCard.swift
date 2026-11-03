import IslandUI
import SwiftUI

/// "Garder mes choix": opt-in, off by default.
struct DefaultAppsGuardCard: View {
    let model: DefaultAppsModel

    var body: some View {
        IslandCard {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                IslandHeader("Garder mes choix",
                             subtitle: "Au lancement et au retour dans l’app, remet vos choix si macOS ou une mise à jour les a réinitialisés. Au plus une fois par heure et par type.")
                IslandRow("Garder mes choix", subtitle: "\(model.storedChoiceCount) choix mémorisé\(model.storedChoiceCount > 1 ? "s" : "")", symbol: "lock.shield") {
                    Toggle(isOn: Bindable(model.settings).guardEnabled) { EmptyView() }
                        .toggleStyle(IslandToggleStyle()).fixedSize().accessibilityLabel("Garder mes choix")
                }
                if !model.recentLog.isEmpty {
                    IslandHeader("Dernières actions")
                    ForEach(Array(model.recentLog.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.islandFootnote).foregroundStyle(IslandPalette.textSecondary.color)
                            .lineLimit(2)
                    }
                }
            }
        }
        .onChange(of: model.settings.guardEnabled) { _, on in
            if on { model.guardCheck(reason: "réglage") }
        }
    }
}
