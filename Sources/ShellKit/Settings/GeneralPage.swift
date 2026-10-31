import AppKit
import IslandUI
import SwiftUI

/// "Général": login item, language, appearance, global shortcut, feedback, quit and relaunch.
struct GeneralPage: View {
    let page: SettingsPage
    let defaults: UserDefaults
    let login: LoginItemModel
    var shortcuts: KeepAwakeShortcutService = .shared

    @State private var language: LanguagePreference = .french
    @State private var appearance: AppearancePreference = .system
    @State private var shortcutOn = true
    @State private var shortcut: ShortcutSpec = .keepAwakeDefault
    @State private var relaunchFailed = false

    var body: some View {
        SettingsPageScaffold(page: page) {
            loginCard
            appearanceCard
            shortcutCard
            feedbackCard
            appCard
        }
        .onAppear {
            language = LanguagePreference.load(from: defaults)
            appearance = AppearancePreference.load(from: defaults)
            shortcutOn = KeepAwakeShortcutService.enabled(in: defaults)
            shortcut = KeepAwakeShortcutService.shortcut(in: defaults)
            login.refresh()
        }
    }

    private var loginCard: some View {
        IslandCard {
            VStack(alignment: .leading, spacing: IslandSpacing.m) {
                VStack(alignment: .leading, spacing: IslandSpacing.xs) {
                    Toggle("Ouvrir à l’ouverture de session", isOn: Binding(get: { login.isOn }, set: { login.set($0) }))
                        .toggleStyle(IslandToggleStyle())
                    HStack(spacing: IslandSpacing.s) {
                        IslandBadge(login.status.badgeText, status: login.status.badgeStatus)
                        Text(login.status.sentence).font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                    }
                    if login.status == .requiresApproval {
                        Button("Ouvrir Réglages Système") { login.openSystemSettings() }.buttonStyle(IslandButtonStyle())
                    }
                    if let message = login.errorMessage {
                        Text(message).font(.islandCaption).foregroundStyle(IslandStatus.danger.color)
                    }
                }
                Divider()
                HStack {
                    Label("Langue", systemImage: "globe").font(.islandBody)
                    Spacer()
                    Picker("Langue", selection: $language) {
                        ForEach(LanguagePreference.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                    .onChange(of: language) { language.save(to: defaults) }
                }
                if !language.isTranslated {
                    Text("Seul le français est traduit pour l’instant : votre choix est gardé pour les traductions à venir.")
                        .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                }
            }
        }
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            IslandHeader("Apparence")
            IslandCard {
                VStack(alignment: .leading, spacing: IslandSpacing.s) {
                    HStack(spacing: IslandSpacing.m) {
                        ForEach(AppearancePreference.allCases) { option in
                            appearanceTile(option)
                        }
                    }
                    Text("Ne concerne que les fenêtres et panneaux de Mac Island, pas tout le Mac.")
                        .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                }
            }
        }
    }

    private func appearanceTile(_ option: AppearancePreference) -> some View {
        let selected = appearance == option
        return Button {
            appearance = option
            option.save(to: defaults)
            option.apply()
        } label: {
            VStack(spacing: IslandSpacing.xs) {
                Image(systemName: option.symbol)
                    .font(.system(size: 22))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(IslandPalette.textPrimary.color.opacity(0.08), in: RoundedRectangle(cornerRadius: IslandRadius.small))
                    .overlay {
                        RoundedRectangle(cornerRadius: IslandRadius.small)
                            .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
                    }
                Text(option.title).font(.islandCaptionEmphasis)
                    .foregroundStyle(selected ? Color.accentColor : IslandPalette.textPrimary.color)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var shortcutCard: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            IslandHeader("Raccourci global")
            IslandCard {
                VStack(alignment: .leading, spacing: IslandSpacing.s) {
                    Toggle("Activer le raccourci pour « Garder éveillé »", isOn: $shortcutOn)
                        .toggleStyle(IslandToggleStyle())
                        .onChange(of: shortcutOn) {
                            defaults.set(shortcutOn, forKey: KeepAwakeShortcutService.enabledKey)
                            shortcuts.refresh()
                        }
                    HStack {
                        Text("Raccourci").font(.islandBody)
                        Spacer()
                        ShortcutRecorderView(spec: shortcut, fallbackText: shortcut.display) { new in
                            shortcut = new
                            defaults.set(new.stored, forKey: KeepAwakeShortcutService.shortcutKey)
                            shortcuts.refresh()
                        }
                        Button("Réinitialiser") {
                            shortcut = .keepAwakeDefault
                            defaults.removeObject(forKey: KeepAwakeShortcutService.shortcutKey)
                            shortcuts.refresh()
                        }
                        .buttonStyle(IslandButtonStyle())
                        .disabled(shortcut == .keepAwakeDefault)
                    }
                    .disabled(!shortcutOn)
                    shortcutStatus
                }
            }
        }
    }

    @ViewBuilder private var shortcutStatus: some View {
        if !shortcuts.isArmed {
            HStack(spacing: IslandSpacing.s) {
                IslandBadge("Pas encore branché", status: .warning)
                Text("Le choix est gardé ; le raccourci n’agit qu’une fois relié à « Garder éveillé » au lancement de l’app.")
                    .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
            }
        } else if shortcutOn && !shortcuts.isRegistered {
            IslandBadge("Refusé par le système : combinaison déjà prise", status: .danger)
        } else if shortcutOn {
            Text("Fonctionne dans toutes les apps, sans autorisation supplémentaire.")
                .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
        }
    }

    private var feedbackCard: some View {
        IslandCard {
            HStack(spacing: IslandSpacing.m) {
                Image(systemName: "bubble.left.and.text.bubble.right").frame(width: 20).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
                    Text("Avis").font(.islandBodyEmphasis)
                    Text("Signalez un bogue ou proposez une idée sur la page du projet.")
                        .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                }
                Spacer()
                Button("Envoyer un avis") {
                    if let url = URL(string: "https://github.com/Roldyy/mac-island/issues/new") { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(IslandButtonStyle())
            }
        }
    }

    private var appCard: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            IslandHeader("Application")
            IslandCard {
                VStack(alignment: .leading, spacing: IslandSpacing.s) {
                    HStack(spacing: IslandSpacing.s) {
                        Button("Relancer Mac Island") { relaunchFailed = !AppLifecycle.relaunch() }
                            .buttonStyle(IslandButtonStyle())
                            .disabled(!AppLifecycle.canRelaunch)
                        Button("Quitter Mac Island") { AppLifecycle.quit() }
                            .buttonStyle(IslandButtonStyle(.destructive))
                    }
                    if !AppLifecycle.canRelaunch {
                        Text("Relancer n’est possible que depuis l’app installée, pas depuis un binaire lancé du terminal.")
                            .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                    }
                    if relaunchFailed {
                        Text("Le relancement a échoué : l’app n’a pas été fermée.")
                            .font(.islandCaption).foregroundStyle(IslandStatus.danger.color)
                    }
                }
            }
        }
    }
}

extension LoginItemStatus {
    var badgeText: String {
        switch self {
        case .enabled: "Actif"
        case .disabled: "Inactif"
        case .requiresApproval: "À approuver"
        case .unavailable: "Indisponible"
        }
    }

    var badgeStatus: IslandStatus {
        switch self {
        case .enabled: .success
        case .disabled: .neutral
        case .requiresApproval: .warning
        case .unavailable: .neutral
        }
    }
}
