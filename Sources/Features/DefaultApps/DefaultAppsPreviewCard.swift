import IslandUI
import SwiftUI

/// What will change, line by line, and what is refused and why. Nothing is written until "Appliquer".
struct DefaultAppsPreviewCard: View {
    let model: DefaultAppsModel
    let preview: ReplacementPreview

    var body: some View {
        IslandCard {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                IslandHeader("Aperçu : rien n’est encore modifié",
                             subtitle: "\(preview.items.count) changement\(preview.items.count > 1 ? "s" : "") vers \(preview.replacement.name).")
                if preview.items.isEmpty {
                    Text("Rien à changer avec ce choix.").font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
                        ForEach(preview.items) { item in
                            IslandRow(item.title, subtitle: subtitle(item), status: item.isProtected ? .warning : nil)
                        }
                    }
                }
                .frame(maxHeight: 220)
                if !preview.refused.isEmpty { refused }
                Text("macOS peut afficher sa propre fenêtre de confirmation : acceptez-la pour chaque type. Si vous la refusez, le reste est interrompu.")
                    .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                HStack(spacing: IslandSpacing.s) {
                    Button("Appliquer \(preview.items.count) changement\(preview.items.count > 1 ? "s" : "")") {
                        Task { await model.confirmAndApply() }
                    }
                    .buttonStyle(IslandButtonStyle(.prominent))
                    .disabled(preview.items.isEmpty || model.isApplying)
                    Button("Annuler") { model.cancelPreview() }.buttonStyle(IslandButtonStyle())
                        .disabled(model.isApplying)
                }
            }
        }
    }

    private func subtitle(_ item: PreviewItem) -> String {
        let ext = item.extensions.isEmpty ? "" : item.extensions.map { "." + $0 }.joined(separator: ", ") + "  ·  "
        return "\(ext)\(item.previousName ?? item.previousBundleID ?? "aucune app") → \(preview.replacement.name)"
    }

    private var refused: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
            IslandHeader("Laissés tels quels", subtitle: "\(preview.refused.count) élément\(preview.refused.count > 1 ? "s" : "").")
            ScrollView {
                VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
                    ForEach(preview.refused) { item in
                        IslandRow(item.title, subtitle: item.reason.text)
                    }
                }
            }
            .frame(maxHeight: 140)
        }
    }
}
