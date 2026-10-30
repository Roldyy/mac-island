import IslandKit
import SwiftUI

struct HistoryPane: View {
    @Bindable var model: ClipboardModel
    @Environment(\.islandActions) private var actions
    @State private var confirmingClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Rechercher", text: $model.query)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    // The keyboard is taken on click only, never on hover.
                    .simultaneousGesture(TapGesture().onEnded { actions.focusKeyboard() })
                    .accessibilityLabel("Rechercher dans l'historique")
                clearControl
            }
            if !model.accessibilityTrusted { accessibilityHint }
            list
        }
    }

    @ViewBuilder private var clearControl: some View {
        if confirmingClear {
            Button("Effacer \(model.unpinnedCount)", role: .destructive) {
                model.clearAll()
                confirmingClear = false
            }
            .accessibilityLabel("Confirmer : effacer \(model.unpinnedCount) éléments non épinglés")
            Button("Annuler") { confirmingClear = false }
        } else {
            Button("Tout effacer", systemImage: "trash") { confirmingClear = true }
                .disabled(model.unpinnedCount == 0)
                .accessibilityLabel("Tout effacer, les éléments épinglés sont gardés")
        }
    }

    private var accessibilityHint: some View {
        HStack {
            Text("Autorisation Accessibilité requise pour coller sans style.")
                .font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            Button("Ouvrir les réglages") { model.openAccessibilitySettings() }
                .font(.caption)
        }
    }

    @ViewBuilder private var list: some View {
        let items = model.visibleEntries
        if items.isEmpty {
            Text(model.query.isEmpty ? "Rien de copié pour l'instant" : "Aucun résultat")
                .font(.callout).foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .center).padding(.top, 16)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(items) { entry in
                        ClipboardRow(entry: entry, model: model)
                    }
                }
            }
        }
    }
}
