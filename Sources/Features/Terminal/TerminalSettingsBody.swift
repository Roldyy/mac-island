import AppKit
import IslandUI
import SwiftUI
import UniformTypeIdentifiers

/// The "Profil de couleurs" part of the Terminal Settings page: import, preview, apply with restart, reset, list.
struct TerminalSettingsBody: View {
    @Bindable var model: TerminalProfilesModel

    var body: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.l) {
            importCard
            if let pending = model.pending {
                TerminalColorProfilePreview(content: TerminalColorProfilePreviewContent(pending))
                pendingActions
            }
            if let confirmation = model.confirmation { confirmationCard(confirmation) }
            if !model.library.profiles.isEmpty { listCard }
        }
        .onAppear { model.reload() }
    }

    // MARK: Import

    private var importCard: some View {
        IslandCard {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                IslandHeader(
                    "Profil de couleurs",
                    subtitle: "Importez un fichier .terminal (Terminal) ou .itermcolors (iTerm2). Le fichier est seulement lu : rien n’y est exécuté.")
                IslandRow("Profil actif", subtitle: model.activeName, symbol: "paintpalette") {
                    Button("Revenir au profil par défaut") { model.resetToDefault() }
                        .buttonStyle(IslandButtonStyle())
                        .disabled(model.library.active == nil)
                        .accessibilityLabel("Revenir au profil de couleurs par défaut")
                }
                HStack {
                    Button("Importer un profil de couleurs…") { chooseFile() }
                        .buttonStyle(IslandButtonStyle())
                        .accessibilityLabel("Importer un profil de couleurs")
                    Spacer()
                }
                if let error = model.errorMessage { message(error, symbol: "exclamationmark.triangle", color: IslandPalette.statusDanger.color) }
                if let status = model.statusMessage { message(status, symbol: "checkmark.circle", color: IslandPalette.statusSuccess.color) }
            }
        }
    }

    private func message(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.islandCaption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
    }

    private var pendingActions: some View {
        HStack(spacing: IslandSpacing.s) {
            Button("Appliquer et redémarrer le terminal") { model.applyPending() }
                .buttonStyle(IslandButtonStyle(.prominent))
                .accessibilityHint("Enregistre le profil puis relance le shell du terminal avec ces couleurs.")
            Button("Annuler") { model.discardPending() }
                .buttonStyle(IslandButtonStyle())
            Spacer()
        }
    }

    private func confirmationCard(_ confirmation: TerminalRestartConfirmation) -> some View {
        IslandCard {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                IslandHeader(
                    "Un programme est en cours",
                    subtitle: "« \(confirmation.process) » tourne dans le terminal. Redémarrer le terminal l’arrêtera et le travail non enregistré sera perdu.")
                HStack(spacing: IslandSpacing.s) {
                    Button("Redémarrer quand même") { model.confirmRestart() }
                        .buttonStyle(IslandButtonStyle(.destructive))
                        .accessibilityLabel("Redémarrer le terminal et arrêter \(confirmation.process)")
                    Button("Annuler") { model.cancelRestart() }
                        .buttonStyle(IslandButtonStyle())
                    Spacer()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Confirmation du redémarrage du terminal")
    }

    // MARK: List

    private var listCard: some View {
        IslandCard {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                IslandHeader("Profils importés", subtitle: "\(model.library.profiles.count) sur \(TerminalProfileLibrary.maxProfiles) au maximum.")
                ForEach(model.library.profiles) { profile in
                    profileRow(profile)
                }
            }
        }
    }

    private func profileRow(_ profile: TerminalColorProfile) -> some View {
        let isActive = model.library.activeID == profile.id
        return HStack(spacing: IslandSpacing.s) {
            HStack(spacing: 1) {
                ForEach(0..<profile.ansi.count, id: \.self) { index in
                    Rectangle().fill(profile.ansi[index].swiftUIColor).frame(width: 7, height: 16)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: IslandRadius.small, style: .continuous))
            .accessibilityHidden(true)
            if model.renamingID == profile.id {
                TextField("Nom du profil", text: $model.renameText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.commitRename() }
                    .accessibilityLabel("Nouveau nom du profil")
                Button("Valider") { model.commitRename() }.buttonStyle(IslandButtonStyle())
                Button("Annuler") { model.cancelRename() }.buttonStyle(IslandButtonStyle())
            } else {
                Text(profile.name)
                    .font(.islandBody)
                    .foregroundStyle(IslandPalette.textPrimary.color)
                    .lineLimit(1)
                if isActive {
                    Text("Actif").font(.islandCaptionEmphasis).foregroundStyle(IslandPalette.statusSuccess.color)
                }
                Spacer(minLength: IslandSpacing.s)
                if !isActive {
                    Button("Appliquer") { model.apply(profile.id) }
                        .buttonStyle(IslandButtonStyle())
                        .accessibilityLabel("Appliquer le profil \(profile.name) et redémarrer le terminal")
                }
                Button("Renommer") { model.beginRename(profile.id) }
                    .buttonStyle(IslandButtonStyle())
                    .accessibilityLabel("Renommer le profil \(profile.name)")
                Button("Supprimer") { model.delete(profile.id) }
                    .buttonStyle(IslandButtonStyle(.destructive))
                    .accessibilityLabel("Supprimer le profil \(profile.name)")
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: File choice

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Importer un profil de couleurs"
        panel.message = "Choisissez un fichier .terminal ou .itermcolors."
        panel.prompt = "Importer"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = TerminalColorProfileParser.supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in model.importFile(at: url) }
        }
    }
}
