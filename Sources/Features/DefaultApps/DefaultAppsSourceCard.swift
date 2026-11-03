import IslandUI
import SwiftUI

/// Step 1: the apps that are the default handler of something. Pick the one to replace.
struct DefaultAppsSourceCard: View {
    let model: DefaultAppsModel

    var body: some View {
        IslandCard {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                IslandHeader("Applications par défaut",
                             subtitle: "Les apps qui ouvrent aujourd’hui au moins un type de fichier. Choisissez celle à remplacer.")
                if model.phase == .scanning {
                    HStack(spacing: IslandSpacing.s) {
                        ProgressView().controlSize(.small)
                        Text("Analyse des apps installées…").font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                    }
                } else if model.replaceable.isEmpty {
                    Text("Aucune app trouvée. Lancez l’analyse.").font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                } else {
                    ScrollView {
                        VStack(spacing: IslandSpacing.xxs) {
                            ForEach(model.replaceable) { app in
                                DefaultAppsSelectRow(
                                    title: app.profile.name,
                                    subtitle: "Ouvre \(app.count) type\(app.count > 1 ? "s" : "") de fichier par défaut",
                                    isSelected: model.selectedSourceID == app.id,
                                    action: { model.selectSource(model.selectedSourceID == app.id ? nil : app.id) },
                                    icon: { AppIconView(url: app.profile.url) })
                            }
                        }
                    }
                    .frame(maxHeight: 230)
                }
                Button("Analyser à nouveau") { Task { await model.refresh() } }
                    .buttonStyle(IslandButtonStyle())
                    .disabled(model.phase == .scanning || model.isApplying)
            }
        }
    }
}
