import SwiftUI

struct DownloadsPane: View {
    @Bindable var model: ShelfModel

    var body: some View {
        Group {
            if !model.downloadsEnabled {
                note("Le suivi des téléchargements est désactivé dans les réglages.")
            } else {
                switch model.downloads.state {
                case .denied:
                    note("macOS bloque l'accès au dossier Téléchargements. Autorisez Mac Island dans Réglages Système > Confidentialité et sécurité > Fichiers et dossiers.")
                case .missing:
                    note("Dossier Téléchargements introuvable.")
                case .ok:
                    if model.downloads.items.isEmpty {
                        note("Aucun téléchargement terminé.")
                    } else {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(model.downloads.items) { item in
                                    FileTile(name: item.name,
                                             icon: model.icon(forPath: item.path),
                                             available: true,
                                             dragProvider: { model.dragProvider(path: item.path) },
                                             reveal: { model.reveal(path: item.path) })
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The way out of "denied": rescan when the pane shows and when the user comes back from
        // System Settings.
        .onAppear { model.refreshDownloads() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshDownloads()
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(text)
    }
}
