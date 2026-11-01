import AppKit
import IslandKit
import IslandUI
import SwiftUI

/// "Avancé": backup and restore of the settings, and help to reset permissions.
struct AdvancedPage: View {
    let page: SettingsPage
    let backup: SettingsBackup
    let openPermission: @MainActor (FeaturePermission) -> Void
    var login: LoginItemModel
    var resetEnvironment: AppReset.Environment = .live

    @State private var confirmingClear = false
    @State private var confirmingUninstall = false
    @State private var backups: [URL] = []
    @State private var message: (text: String, status: IslandStatus)?
    @State private var pendingRestore: URL?

    var body: some View {
        SettingsPageScaffold(page: page) {
            backupCard
            permissionsCard
            uninstallCard
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
        .confirmationDialog("Effacer toutes les autorisations ?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Effacer les autorisations", role: .destructive) {
                message = appReset.clearPermissions().asMessage
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Mac Island perd l’Accessibilité, l’Enregistrement de l’écran, l’Accès complet au disque et ses autres autorisations, et ne s’ouvre plus à la connexion. L’app reste installée.")
        }
        .confirmationDialog("Désinstaller complètement Mac Island ?", isPresented: $confirmingUninstall, titleVisibility: .visible) {
            Button("Désinstaller", role: .destructive) {
                appReset.uninstallCompletely { message = $0.asMessage }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Retire les autorisations et l’ouverture à la connexion, supprime les réglages, les sauvegardes et les dossiers de l’app, puis place Mac Island dans la corbeille et quitte. Exportez vos réglages avant si vous voulez les garder.")
        }
    }

    private var appReset: AppReset { AppReset(login: login, environment: resetEnvironment) }

    private var backupCard: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            IslandHeader("Sauvegarde", subtitle: "Emportez votre configuration sur un autre Mac : exportez toutes les préférences dans un fichier et importez-le là-bas. Le texte de vos notes dans Brouillon, l’historique du presse-papiers, les éléments de l’étagère et les autorisations système ne quittent jamais ce Mac.")
            SettingsCard {
                VStack(alignment: .leading, spacing: IslandSpacing.s) {
                    HStack(spacing: IslandSpacing.s) {
                        Button("Sauvegarder maintenant", systemImage: "square.and.arrow.up") { save() }
                            .buttonStyle(IslandButtonStyle(.prominent))
                        Button("Afficher le dossier", systemImage: "folder") { reveal() }
                            .buttonStyle(IslandButtonStyle())
                    }
                    HStack(spacing: IslandSpacing.s) {
                        Button("Exporter les réglages…", systemImage: "square.and.arrow.up.on.square") { exportToChosenFile() }
                            .buttonStyle(IslandButtonStyle())
                        Button("Importer les réglages…", systemImage: "square.and.arrow.down") { chooseFileToImport() }
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
            IslandHeader("Autorisations", subtitle: "Retire toutes les autorisations que vous avez accordées à Mac Island (Accessibilité, Enregistrement de l’écran, Accès complet au disque et autres) et l’élément d’ouverture à la connexion. Utile pour repartir de zéro ou avant de désinstaller. L’app reste installée.")
            SettingsCard {
                VStack(alignment: .leading, spacing: IslandSpacing.s) {
                    Button("Effacer toutes les autorisations", systemImage: "hand.raised.slash") { confirmingClear = true }
                        .buttonStyle(IslandButtonStyle())
                    Divider()
                    Text("Revoir une autorisation").font(.islandBodyEmphasis)
                    HStack(spacing: IslandSpacing.s) {
                        ForEach([FeaturePermission.accessibility, .screenRecording, .automation, .audioCapture], id: \.self) { p in
                            Button(p.title) { openPermission(p) }.buttonStyle(IslandButtonStyle())
                        }
                    }
                }
            }
        }
    }

    private var uninstallCard: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            IslandHeader("Désinstaller", subtitle: "Fait tout ce qui précède, puis supprime les préférences et place Mac Island dans la corbeille, sans rien laisser. L’app quitte une fois terminé. Vous pouvez réinstaller à tout moment. L’assistant des ventilateurs et la règle d’écran rabattu (/etc/sudoers.d/macisland-clamshell) demandent un mot de passe administrateur : s’ils ont été installés, ils restent à retirer à la main (Réglages Système, Général, Ouverture et extensions ; sudo rm pour la règle).")
            SettingsCard {
                Button("Désinstaller complètement Mac Island", systemImage: "trash") { confirmingUninstall = true }
                    .buttonStyle(IslandButtonStyle())
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

    /// Writes a backup (same format as the folder ones) where the person chooses, for another Mac.
    private func exportToChosenFile() {
        do {
            let source = try backup.export()
            backups = backup.list()
            let panel = NSSavePanel()
            panel.nameFieldStringValue = source.lastPathComponent
            panel.allowedContentTypes = [.propertyList]
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let target = panel.url else {
                message = ("Sauvegarde gardée dans le dossier Sauvegardes : \(source.lastPathComponent)", .info)
                return
            }
            // The panel already asked before replacing a file of that name.
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: source, to: target)
            message = ("Réglages exportés : \(target.lastPathComponent)", .success)
        } catch {
            message = ("L’export a échoué : \(error.localizedDescription)", .danger)
        }
    }

    /// Picks a backup file; the usual confirmation then asks before it replaces today's values.
    private func chooseFileToImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { pendingRestore = url }
    }

    private func reveal() {
        try? FileManager.default.createDirectory(at: backup.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([backup.directory])
    }
}

extension AppReset.Outcome {
    /// The line the page shows under the cards.
    var asMessage: (text: String, status: IslandStatus) {
        switch self {
        case .done(let text): (text, .success)
        case .partial(let text): (text, .warning)
        }
    }
}
