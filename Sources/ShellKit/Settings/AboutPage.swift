import AppKit
import IslandUI
import SwiftUI

/// "À propos": version, licence, links, and the "Mises à jour" block (the four preferences and the check).
struct AboutPage: View {
    let page: SettingsPage
    var defaults: UserDefaults = .standard
    /// Opens another Settings page ("Revoir l'introduction", "Revoir les nouveautés").
    var navigate: @MainActor (String) -> Void = { _ in }
    var checker: UpdateChecker = .shared

    static func version(bundle: Bundle = .main) -> String { AboutVersion.current(bundle: bundle) }

    var body: some View {
        SettingsPageScaffold(page: page) {
            identityCard
            RoldyCreditCard()
            linksCard
            UpdatesBlock(defaults: defaults, checker: checker)
        }
    }

    private var identityCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                HStack(spacing: IslandSpacing.m) {
                    Image(systemName: "rectangle.topthird.inset.filled")
                        .font(.system(size: 34)).foregroundStyle(Color.accentColor).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
                        Text("Mac Island").font(.system(size: 17, weight: .semibold))
                        Text("Version \(Self.version())").font(.islandCaption)
                            .foregroundStyle(IslandPalette.textSecondary.color)
                    }
                }
                Text("Un centre d’utilitaires pour votre Mac, sous l’encoche : agents, presse-papiers, étagère, mixeur, moniteur, défilement et sélecteur de fenêtres.")
                    .font(.islandBody).foregroundStyle(IslandPalette.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: IslandSpacing.s) {
                    Button("Revoir l’introduction") { navigate("features") }
                        .buttonStyle(IslandButtonStyle())
                        .help("Ouvre la page Fonctions : c’est là que l’on choisit ce que Mac Island fait.")
                    Button("Revoir les nouveautés") { navigate("whatsnew") }
                        .buttonStyle(IslandButtonStyle())
                }
            }
        }
    }

    private var linksCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                link("Voir sur GitHub", "chevron.left.forwardslash.chevron.right", "https://github.com/Roldyy/mac-island")
                link("Lire la licence (GPL-3.0)", "doc.text", "https://github.com/Roldyy/mac-island/blob/main/LICENSE")
                link("Signaler un problème", "exclamationmark.bubble", "https://github.com/Roldyy/mac-island/issues")
                Divider()
                Text("© 2026 Roldy Management. Logiciel libre sous licence GPL-3.0 ou ultérieure, en partie dérivé de Vorssaint.")
                    .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func link(_ title: String, _ symbol: String, _ url: String) -> some View {
        Button(title, systemImage: symbol) {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        }
        .buttonStyle(IslandButtonStyle())
    }
}

/// "Mises à jour": `autoCheckUpdates`, `includeBetaUpdates`, `showReleaseNotesBeforeUpdate` and `releaseNotesOnUpdate`
/// (the migrated keys), then the result of the last check with its two buttons.
struct UpdatesBlock: View {
    let defaults: UserDefaults
    let checker: UpdateChecker

    @State private var auto: Bool
    @State private var beta: Bool
    @State private var notesBefore: Bool
    @State private var notesAfter: Bool

    init(defaults: UserDefaults, checker: UpdateChecker) {
        self.defaults = defaults
        self.checker = checker
        func flag(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        _auto = State(initialValue: flag(UpdateChecker.autoKey, true))
        _beta = State(initialValue: flag(UpdateChecker.betaKey, false))
        _notesBefore = State(initialValue: flag("showReleaseNotesBeforeUpdate", true))
        _notesAfter = State(initialValue: flag("releaseNotesOnUpdate", true))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            IslandHeader("Mises à jour")
            SettingsCard {
                VStack(alignment: .leading, spacing: IslandSpacing.s) {
                    row("Rechercher les mises à jour automatiquement", $auto, UpdateChecker.autoKey,
                        hint: "Une recherche par jour au plus, à l’ouverture des Réglages. Rien n’est envoyé à part la demande à GitHub.")
                    row("Recevoir les mises à jour bêta", $beta, UpdateChecker.betaKey,
                        hint: "Les versions bêta incluent des fonctionnalités en cours de développement et peuvent présenter des instabilités.")
                    row("Afficher les nouveautés avant la mise à jour", $notesBefore, "showReleaseNotesBeforeUpdate",
                        hint: "Ce qui a changé dans vos fonctions s’affiche toujours après chaque mise à jour.")
                    row("Afficher les nouveautés après mise à jour", $notesAfter, "releaseNotesOnUpdate", hint: nil)
                    Divider()
                    status
                    HStack(spacing: IslandSpacing.s) {
                        Button("Rechercher maintenant") { Task { await checker.check(defaults: defaults) } }
                            .buttonStyle(IslandButtonStyle())
                            .disabled(checker.state == .checking)
                        if case .available(let release) = checker.state {
                            Button("Télécharger la mise à jour") { NSWorkspace.shared.open(release.pageURL) }
                                .buttonStyle(IslandButtonStyle(.prominent))
                                .help("Ouvre la page de la version. Une app ne peut pas se remplacer pendant qu’elle tourne : glissez la nouvelle app dans Applications.")
                        }
                    }
                    if case .available(let release) = checker.state {
                        if notesBefore, !release.notes.isEmpty {
                            Text(String(release.notes.prefix(700)))
                                .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }
                        Text("Mac Island ne se remplace pas lui-même : la page de la version s’ouvre dans votre navigateur, et vous glissez la nouvelle app dans Applications.")
                            .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let last = checker.lastCheck {
                        Text("Dernière recherche : \(last.formatted(date: .numeric, time: .shortened))")
                            .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                    }
                }
            }
        }
        .task { checker.loadLastCheck(from: defaults) }
    }

    @ViewBuilder private var status: some View {
        switch checker.state {
        case .idle:
            EmptyView()
        case .checking:
            Label("Recherche en cours…", systemImage: "arrow.triangle.2.circlepath").font(.islandBody)
        case .upToDate:
            Label("Mac Island est à jour.", systemImage: "checkmark.circle").font(.islandBody)
        case .available(let release):
            Label("Mise à jour disponible : \(release.tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")))",
                  systemImage: "arrow.down.circle").font(.islandBodyEmphasis)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle").font(.islandBody)
                .foregroundStyle(IslandStatus.danger.color)
        }
    }

    private func row(_ title: String, _ value: Binding<Bool>, _ key: String, hint: String?) -> some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
            HStack(spacing: IslandSpacing.s) {
                Text(title).font(.islandBody).frame(maxWidth: .infinity, alignment: .leading)
                Toggle(isOn: value) { EmptyView() }
                    .toggleStyle(IslandToggleStyle()).fixedSize()
                    .accessibilityLabel(title)
                    .onChange(of: value.wrappedValue) { _, on in defaults.set(on, forKey: key) }
            }
            if let hint {
                Text(hint).font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
