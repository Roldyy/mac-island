import AppKit
import IslandKit
import IslandUI
import SwiftUI

/// "Avancé": backup and restore of the settings, and help to reset permissions.
struct AdvancedPage: View {
    let page: SettingsPage
    let backup: SettingsBackup
    let openPermission: @MainActor (FeaturePermission) -> Void

    @State private var backups: [URL] = []
    @State private var message: (text: String, status: IslandStatus)?
    @State private var pendingRestore: URL?
    @State private var copied = false

    static let resetCommand = "tccutil reset All be.roldy.macisland"

    var body: some View {
        SettingsPageScaffold(page: page) {
            backupCard
            permissionsCard
        }
        .task {
            // The folder is read off the main thread; the page shows "Aucune sauvegarde" for a moment at worst.
            let directory = backup.directory
            backups = await Task.detached(priority: .userInitiated) { SettingsBackup.list(in: directory) }.value
        }
        .confirmationDialog("Restaurer ces réglages ?", isPresented: Binding(
            get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }), titleVisibility: .visible) {
            Button("Restaurer", role: .destructive) { restore() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les valeurs du fichier remplacent celles d’aujourd’hui. Relancez l’app ensuite pour que tout en tienne compte.")
        }
    }

    private var backupCard: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            IslandHeader("Sauvegarde", subtitle: "Vos réglages sont copiés dans un fichier du dossier Sauvegardes. Rien d’autre : ni presse-papiers, ni étagère, ni autorisations.")
            SettingsCard {
                VStack(alignment: .leading, spacing: IslandSpacing.s) {
                    HStack(spacing: IslandSpacing.s) {
                        Button("Sauvegarder maintenant", systemImage: "square.and.arrow.up") { save() }
                            .buttonStyle(IslandButtonStyle(.prominent))
                        Button("Afficher le dossier", systemImage: "folder") { reveal() }
                            .buttonStyle(IslandButtonStyle())
                    }
                    if let message {
                        HStack(spacing: IslandSpacing.xs) {
                            Image(systemName: message.status.symbol).accessibilityHidden(true)
                            Text(message.text)
                        }
                        .font(.islandCaption).foregroundStyle(message.status.color)
                    }
                    if backups.isEmpty {
                        Text("Aucune sauvegarde pour l’instant.").font(.islandCaption)
                            .foregroundStyle(IslandPalette.textSecondary.color)
                    } else {
                        ForEach(backups.prefix(8), id: \.self) { url in
                            HStack {
                                Image(systemName: "doc.text").accessibilityHidden(true)
                                Text(url.deletingPathExtension().lastPathComponent).font(.islandValue)
                                Spacer()
                                Button("Restaurer") { pendingRestore = url }.buttonStyle(IslandButtonStyle())
                            }
                        }
                    }
                }
            }
        }
    }

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            IslandHeader("Autorisations", subtitle: "Mac Island ne peut pas retirer ses autorisations lui-même : macOS les garde. Voici comment les revoir ou repartir de zéro.")
            SettingsCard {
                VStack(alignment: .leading, spacing: IslandSpacing.s) {
                    Text("Revoir une autorisation").font(.islandBodyEmphasis)
                    HStack(spacing: IslandSpacing.s) {
                        ForEach([FeaturePermission.accessibility, .screenRecording, .automation, .audioCapture], id: \.self) { p in
                            Button(p.title) { openPermission(p) }.buttonStyle(IslandButtonStyle())
                        }
                    }
                    Divider()
                    Text("Tout effacer").font(.islandBodyEmphasis)
                    Text("Collez cette commande dans le Terminal, puis relancez l’app : macOS redemandera chaque autorisation au moment du besoin.")
                        .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                    HStack {
                        Text(Self.resetCommand).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        Spacer()
                        Button(copied ? "Copié" : "Copier") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(Self.resetCommand, forType: .string)
                            copied = true
                        }
                        .buttonStyle(IslandButtonStyle())
                    }
                }
            }
        }
    }

    private func save() {
        do {
            let url = try backup.export()
            backups = backup.list()
            message = ("Sauvegarde créée : \(url.lastPathComponent)", .success)
        } catch {
            message = ("La sauvegarde a échoué : \(error.localizedDescription)", .danger)
        }
    }

    private func restore() {
        guard let url = pendingRestore else { return }
        pendingRestore = nil
        do {
            try backup.restore(from: url)
            message = ("Réglages restaurés. Relancez l’app pour finir.", .success)
        } catch {
            message = ("Ce fichier n’est pas une sauvegarde valide.", .danger)
        }
    }

    private func reveal() {
        try? FileManager.default.createDirectory(at: backup.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([backup.directory])
    }
}
