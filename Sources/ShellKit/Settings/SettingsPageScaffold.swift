import IslandKit
import IslandUI
import SwiftUI

/// Title, one-line summary and the cards of a page, in a scroll view.
struct SettingsPageScaffold<Content: View>: View {
    let page: SettingsPage
    let content: Content

    init(page: SettingsPage, @ViewBuilder content: () -> Content) {
        self.page = page
        self.content = content()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: IslandSpacing.l) {
                VStack(alignment: .leading, spacing: IslandSpacing.xs) {
                    HStack(spacing: IslandSpacing.s) {
                        Text(page.title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(IslandPalette.textPrimary.color)
                            .accessibilityAddTraits(.isHeader)
                        if page.isComingSoon { IslandBadge("Bientôt", status: .info) }
                    }
                    Text(page.summary)
                        .font(.islandBody)
                        .foregroundStyle(IslandPalette.textSecondary.color)
                }
                content
            }
            .padding(IslandSpacing.xl)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Switch and live status of the registry feature a page belongs to.
struct FeatureStatusCard: View {
    let registry: FeatureRegistry
    let featureID: String
    let openPermission: @MainActor (FeaturePermission) -> Void

    var body: some View {
        if let d = registry.descriptor(featureID) {
            let state = registry.state(for: featureID)
            let badge = registry.needsRelaunch(featureID) ? FeatureBadge.pendingRelaunch : FeatureBadge(state)
            SettingsCard {
                VStack(alignment: .leading, spacing: IslandSpacing.s) {
                    HStack(spacing: IslandSpacing.s) {
                        Image(systemName: d.systemImage).frame(width: 20)
                            .foregroundStyle(IslandPalette.textSecondary.color).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
                            Text(d.title).font(.islandBodyEmphasis)
                            Text(d.summary).font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                        }
                        Spacer()
                        Toggle(isOn: Bindable(registry)[feature: featureID]) { EmptyView() }
                            .toggleStyle(IslandToggleStyle()).fixedSize()
                            .accessibilityLabel(d.title)
                    }
                    HStack {
                        IslandBadge(badge.text, status: badge.status)
                        Spacer()
                        if case .needsPermission(let permission) = state {
                            Button("Autoriser") { openPermission(permission) }.buttonStyle(IslandButtonStyle())
                        }
                        if state == .quarantined {
                            Button("Réactiver") { registry.clearQuarantine(featureID) }.buttonStyle(IslandButtonStyle())
                        }
                    }
                }
            }
        }
    }
}
