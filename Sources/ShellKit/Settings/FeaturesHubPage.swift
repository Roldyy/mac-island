import IslandKit
import AppKit
import IslandUI
import SwiftUI

/// The feature hub: one switch per feature, grouped by category.
struct FeaturesHubPage: View {
    @Bindable var registry: FeatureRegistry
    /// Tabs of features that have no place in the island's four groups: their settings open in a sheet.
    let sheetTabs: [String: IslandTab]
    let openPermission: @MainActor (FeaturePermission) -> Void
    /// Restarts the app; nil when it cannot (a bare `swift run` binary), then the row only says so.
    var relaunch: (@MainActor () -> Void)?

    @State private var query = ""
    @State private var sheetTab: IslandTab?
    @State private var hooksCopied = false
    @State private var confirmUninstallAll = false

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            List {
                ForEach(FeatureHub.sections(registry.descriptors, query: query), id: \.category) { section in
                    Section {
                        ForEach(section.features) { row($0) }
                    } header: {
                        IslandHeader(section.category.title)
                    }
                }
                Section { claudeHooks } header: { IslandHeader("Claude") }
            }
        }
        .sheet(item: $sheetTab) { tab in
            VStack(spacing: 0) {
                HStack {
                    IslandHeader(tab.title)
                    Spacer()
                    Button("Fermer") { sheetTab = nil }.buttonStyle(IslandButtonStyle())
                }
                .padding(12)
                tab.makeView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minWidth: 640, minHeight: 400)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            PermissionStatusCard(registry: registry, relaunch: relaunch)
            TextField("Rechercher une fonction", text: $query)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                Text("Ensembles").font(.system(size: 12)).foregroundStyle(.secondary)
                ForEach(FeatureBundle.allCases) { bundle in
                    Button(bundle.title) { registry.apply(bundle) }.buttonStyle(IslandButtonStyle())
                }
                Spacer()
            }
            let installed = registry.descriptors.filter { registry.isEnabled($0.id) }.count
            HStack(spacing: 8) {
                Text("\(installed) fonctions sur \(registry.descriptors.count) installées")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Tout installer") { registry.apply(.tout) }.buttonStyle(IslandButtonStyle())
                Button("Tout désinstaller") { confirmUninstallAll = true }.buttonStyle(IslandButtonStyle(.destructive))
            }
            .confirmationDialog("Désinstaller toutes les fonctions ?", isPresented: $confirmUninstallAll) {
                Button("Tout désinstaller", role: .destructive) {
                    for d in registry.descriptors { _ = registry.setSwitch(d.id, to: false) }
                }
            } message: {
                Text("Chaque interrupteur passe sur arrêt. Vous pouvez les rallumer un par un, ou avec « Tout installer ».")
            }
            Toggle("Mode sans échec (garde seulement les fonctions du quotidien)", isOn: $registry.safeMode)
                .toggleStyle(IslandToggleStyle())
            Toggle("Interrupteur général (coupe toutes les fonctions)", isOn: $registry.killSwitch)
                .toggleStyle(IslandToggleStyle())
        }
        .font(.system(size: 12))
        .padding(12)
    }

    /// Optional hooks: the island reacts faster than the 2 s poll. Display and copy only.
    private var claudeHooks: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Réaction immédiate aux sessions Claude Code (facultatif)")
                .font(.system(size: 13, weight: .medium))
            Text("Mac Island n'écrit jamais dans votre fichier ~/.claude/settings.json. Copiez ce bloc, puis collez-le vous-même dans ce fichier.")
                .font(.system(size: 11)).foregroundStyle(IslandPalette.textSecondary.color)
            HStack(spacing: 8) {
                Button(hooksCopied ? "Copié" : "Copier le bloc de hooks") { copyHooks() }
                    .buttonStyle(IslandButtonStyle())
                    .disabled(ClaudeHookSetup.snippet() == nil)
                if ClaudeHookSetup.snippet() == nil {
                    Text("Introuvable : disponible dans l'app installée.")
                        .font(.system(size: 11)).foregroundStyle(IslandPalette.textSecondary.color)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func copyHooks() {
        guard let snippet = ClaudeHookSetup.snippet() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snippet, forType: .string)
        hooksCopied = true
    }

    private func row(_ d: FeatureDescriptor) -> some View {
        let state = registry.state(for: d.id)
        let relaunchNeeded = registry.needsRelaunch(d.id)
        let badge = relaunchNeeded ? FeatureBadge.pendingRelaunch : FeatureBadge(state)
        return HStack(spacing: 10) {
            Image(systemName: d.systemImage).frame(width: 24).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(d.title).font(.system(size: 13, weight: .medium))
                Text(d.summary).font(.system(size: 11)).foregroundStyle(.secondary)
                Label(badge.text, systemImage: badge.status.symbol)
                    .font(.system(size: 11)).foregroundStyle(badge.status.color)
            }
            Spacer(minLength: 8)
            if relaunchNeeded, let relaunch {
                Button("Relancer") { relaunch() }.buttonStyle(IslandButtonStyle())
            }
            if case .needsPermission(let permission) = state {
                Button("Autoriser") {
                    PermissionClick.perform(permission, featureID: d.id, registry: registry, openPermission: openPermission)
                }
                    .buttonStyle(IslandButtonStyle())
            }
            if state == .quarantined {
                Button("Réactiver") { registry.clearQuarantine(d.id) }.buttonStyle(IslandButtonStyle())
            }
            if let tabID = d.tabID, let tab = sheetTabs[tabID] {
                Button("Réglages") { sheetTab = tab }.buttonStyle(IslandButtonStyle())
            }
            // IslandToggleStyle draws its label itself (`labelsHidden` does not reach it): an empty label, named for VoiceOver.
            Toggle(isOn: $registry[feature: d.id]) { EmptyView() }
                .toggleStyle(IslandToggleStyle())
                .fixedSize()
                .accessibilityLabel(d.title)
        }
        .padding(.vertical, 3)
    }
}
