import IslandUI
import SwiftUI

/// The last replacement, and the two undo buttons (each asks once more before it writes).
struct DefaultAppsHistoryCard: View {
    let model: DefaultAppsModel

    var body: some View {
        IslandCard {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                IslandHeader("Historique et annulation",
                             subtitle: "Avant chaque changement, l’ancienne app de chaque type est notée. L’annulation ne touche que ce que vous n’avez pas modifié depuis.")
                if let notice = model.journalNotice {
                    IslandBadge(notice, status: .warning)
                }
                if let last = model.lastEntry {
                    IslandRow("\(last.sourceName ?? "Schéma d’URL") → \(last.replacementName)",
                              subtitle: "\(last.changes.count) élément\(last.changes.count > 1 ? "s" : "") · \(last.date.formatted(date: .abbreviated, time: .shortened))",
                              symbol: "clock.arrow.circlepath")
                    Text("\(model.journalEntries.count) remplacement\(model.journalEntries.count > 1 ? "s" : "") enregistré\(model.journalEntries.count > 1 ? "s" : "").")
                        .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                } else {
                    Text("Aucun remplacement enregistré.").font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                }
                if let pending = model.pending { confirmation(pending) }
                HStack(spacing: IslandSpacing.s) {
                    Button("Annuler le dernier remplacement") { model.requestUndoLast() }
                        .buttonStyle(IslandButtonStyle())
                    Button("Tout restaurer") { model.requestRestoreAll() }
                        .buttonStyle(IslandButtonStyle())
                }
                .disabled(model.journalEntries.isEmpty || model.isApplying || model.pending != nil)
            }
        }
    }

    private func confirmation(_ pending: DefaultAppsModel.Pending) -> some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            Text(pending == .undoLast
                 ? "Remettre le dernier remplacement comme avant ?"
                 : "Remettre tous les remplacements enregistrés comme avant ?")
                .font(.islandCaption).foregroundStyle(IslandPalette.textPrimary.color)
            HStack(spacing: IslandSpacing.s) {
                Button("Confirmer") { Task { await model.confirmPending() } }.buttonStyle(IslandButtonStyle(.prominent))
                Button("Annuler") { model.cancelPending() }.buttonStyle(IslandButtonStyle())
            }
        }
    }
}
