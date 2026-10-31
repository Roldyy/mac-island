import IslandKit
import IslandUI
import SwiftUI

/// The feature hub: one switch per feature, grouped by category.
struct SettingsView: View {
    @Bindable var registry: FeatureRegistry
    /// Tabs of features that have no place in the island's four groups: their settings open in a sheet.
    let sheetTabs: [String: IslandTab]
    let openPermission: @MainActor (FeaturePermission) -> Void

    @State private var query = ""
    @State private var sheetTab: IslandTab?

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
            }
        }
        .frame(minWidth: 560, minHeight: 480)
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
            TextField("Rechercher une fonction", text: $query)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                Text("Ensembles").font(.system(size: 12)).foregroundStyle(.secondary)
                ForEach(FeatureBundle.allCases) { bundle in
                    Button(bundle.title) { registry.apply(bundle) }.buttonStyle(IslandButtonStyle())
                }
                Spacer()
            }
            Toggle("Mode sans échec (garde seulement les fonctions du quotidien)", isOn: $registry.safeMode)
                .toggleStyle(IslandToggleStyle())
            Toggle("Interrupteur général (coupe toutes les fonctions)", isOn: $registry.killSwitch)
                .toggleStyle(IslandToggleStyle())
        }
        .font(.system(size: 12))
        .padding(12)
    }

    private func row(_ d: FeatureDescriptor) -> some View {
        let state = registry.state(for: d.id)
        let badge = FeatureBadge(state)
        return HStack(spacing: 10) {
            Image(systemName: d.systemImage).frame(width: 24).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(d.title).font(.system(size: 13, weight: .medium))
                Text(d.summary).font(.system(size: 11)).foregroundStyle(.secondary)
                Label(badge.text, systemImage: badge.status.symbol)
                    .font(.system(size: 11)).foregroundStyle(badge.status.color)
            }
            Spacer(minLength: 8)
            if case .needsPermission(let permission) = state {
                Button("Autoriser") { openPermission(permission) }.buttonStyle(IslandButtonStyle())
            }
            if state == .quarantined {
                Button("Réactiver") { registry.clearQuarantine(d.id) }.buttonStyle(IslandButtonStyle())
            }
            if let tabID = d.tabID, let tab = sheetTabs[tabID] {
                Button("Réglages") { sheetTab = tab }.buttonStyle(IslandButtonStyle())
            }
            Toggle(d.title, isOn: $registry[feature: d.id])
                .labelsHidden()
                .toggleStyle(IslandToggleStyle())
        }
        .padding(.vertical, 3)
    }
}
