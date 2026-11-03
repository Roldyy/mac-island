import IslandUI
import SwiftUI

/// Step 2: the types of the chosen app, the replacement app, all types or a picked few.
struct DefaultAppsReplacementCard: View {
    let model: DefaultAppsModel

    var body: some View {
        if let source = model.source {
            IslandCard {
                VStack(alignment: .leading, spacing: IslandSpacing.s) {
                    IslandHeader("Remplacer \(source.profile.name)",
                                 subtitle: "\(source.count) type\(source.count > 1 ? "s" : "") ouvert\(source.count > 1 ? "s" : "") par défaut. Rien n’est modifié avant l’aperçu et votre confirmation.")
                    modePicker
                    typeList(source)
                    protectedList(source)
                    replacementList
                    Button("Voir l’aperçu des changements") { model.buildPreview() }
                        .buttonStyle(IslandButtonStyle(.prominent))
                        .disabled(!canPreview)
                }
            }
        }
    }

    private var canPreview: Bool {
        guard model.replacement != nil, !model.isApplying else { return false }
        return model.mode == .all || !model.pickedTypes.isEmpty
    }

    private var modePicker: some View {
        HStack(spacing: IslandSpacing.s) {
            Button("Remplacer pour tous les types") { model.setMode(.all) }
                .buttonStyle(IslandButtonStyle(model.mode == .all ? .prominent : .standard))
            Button("Choisir les types") { model.setMode(.pick) }
                .buttonStyle(IslandButtonStyle(model.mode == .pick ? .prominent : .standard))
        }
    }

    @ViewBuilder private func typeList(_ source: ReplaceableApp) -> some View {
        let plain = source.handled.filter { !$0.isProtected }
        Text(model.mode == .all
             ? "Tous ces types passent à l’app choisie, sauf ceux qu’elle ne sait pas ouvrir (ils restent chez \(source.profile.name))."
             : "Cochez les types à remplacer.")
            .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
        ScrollView {
            VStack(alignment: .leading, spacing: IslandSpacing.xs) {
                ForEach(plain) { type in
                    DefaultAppsCheckRow(title: type.summary, subtitle: detail(type),
                                        isOn: model.mode == .all || model.pickedTypes.contains(type.id),
                                        isEnabled: model.mode == .pick) { model.togglePicked(type.id) }
                }
            }
        }
        .frame(maxHeight: 200)
    }

    @ViewBuilder private func protectedList(_ source: ReplaceableApp) -> some View {
        let locked = source.handled.filter(\.isProtected)
        if !locked.isEmpty {
            VStack(alignment: .leading, spacing: IslandSpacing.xs) {
                IslandBadge("Types protégés", status: .warning)
                Text("Jamais inclus dans « tous les types ». Ne les cochez que si vous savez ce que vous faites.")
                    .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                ForEach(locked) { type in
                    DefaultAppsCheckRow(title: type.summary, subtitle: detail(type),
                                        isOn: model.explicitProtected.contains(type.id)) {
                        model.setProtectedConfirmed(type.id, !model.explicitProtected.contains(type.id))
                    }
                }
            }
        }
    }

    private var replacementList: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            IslandHeader("Remplacer par", subtitle: "Les apps installées qui déclarent pouvoir ouvrir ces types.")
            if model.candidates.isEmpty {
                Text("Aucune autre app installée ne déclare pouvoir ouvrir ces types.")
                    .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
            } else {
                ScrollView {
                    VStack(spacing: IslandSpacing.xxs) {
                        ForEach(model.candidates) { candidate in
                            DefaultAppsSelectRow(
                                title: candidate.profile.name,
                                subtitle: "Peut ouvrir \(candidate.coverage) de ces types",
                                isSelected: model.selectedReplacementID == candidate.id,
                                action: { model.selectReplacement(candidate.id) },
                                icon: { AppIconView(url: candidate.profile.url) })
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
    }

    private func detail(_ type: HandledType) -> String {
        type.extensions.isEmpty ? type.id : "\(type.extensionsText)  ·  \(type.id)"
    }
}
