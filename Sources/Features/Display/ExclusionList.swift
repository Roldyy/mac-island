import SwiftUI

/// Bundle ids never quit. Added from the running apps list: no text field, so the island
/// never needs the keyboard.
struct ExclusionList: View {
    let model: AutoQuitModel

    private var addable: [AppSnapshot] {
        model.candidatesToExclude.filter { app in
            guard let id = app.bundleID else { return false }
            return !model.exclusions.contains(id) && !AutoQuitConfig.builtInExclusions.contains(id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Jamais quitter").font(.subheadline.weight(.semibold))
                Spacer()
                Menu("Ajouter une app", systemImage: "plus") {
                    ForEach(addable, id: \.pid) { app in
                        Button(app.name) { if let id = app.bundleID { model.addExclusion(id) } }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(addable.isEmpty)
                .accessibilityLabel("Ajouter une app à la liste d'exclusion")
            }
            if model.exclusions.isEmpty {
                Text("Toujours exclus : Finder, Dock, apps de barre des menus, app au premier plan ou qui joue du son.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.exclusions, id: \.self) { id in
                HStack {
                    Text(id).font(.caption.monospaced()).lineLimit(1)
                    Spacer()
                    Button("Retirer", systemImage: "minus.circle") { model.removeExclusion(id) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .accessibilityLabel("Retirer \(id) de la liste")
                }
            }
        }
    }
}
