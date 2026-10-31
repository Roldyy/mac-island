import IslandKit
import IslandUI
import SwiftUI

/// "Explorer": every feature panel in a grid. A tap opens the panel inside the island.
struct ExploreView: View {
    let context: ShellContext

    var body: some View {
        VStack(spacing: 0) {
            HomeBackHeader(title: "Explorer", context: context)
            grid.frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, IslandSpacing.l - 2)
    }

    private var grid: some View {
        let columns = HomeGeometry.exploreColumns
        let items = context.exploreTabIDs.compactMap { id in context.tabs.first { $0.id == id } }
        let rows = stride(from: 0, to: items.count, by: columns).map { Array(items[$0..<min($0 + columns, items.count)]) }
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(row) { tile($0) }
                    ForEach(0..<(columns - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
                .frame(height: HomeGeometry.exploreRow)
            }
        }
    }

    private func tile(_ tab: IslandTab) -> some View {
        let enabled = context.registry.isEnabled(tab.id)
        return Button {
            if enabled { context.navigation.open(tabID: tab.id) } else { context.openSettings() }
        } label: {
            VStack(spacing: IslandSpacing.xs) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(IslandPalette.textPrimary.color)
                    .frame(width: 44, height: 44)
                    .background(IslandPalette.textPrimary.color.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: IslandRadius.large, style: .continuous))
                Text(tab.title)
                    .font(.system(size: IslandType.minimumSize, weight: .medium))
                    .foregroundStyle(IslandPalette.textPrimary.color)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Rectangle())
        }
        .buttonStyle(HomeTapStyle())
        .help(enabled ? tab.title : "\(tab.title) : désactivé. Ouvre les Réglages pour l'activer.")
        .accessibilityLabel(enabled ? tab.title : "\(tab.title), désactivé")
    }
}

/// Back chevron + title, shared by the Explorer and by a feature page.
struct HomeBackHeader<Trailing: View>: View {
    let title: String
    let context: ShellContext
    @ViewBuilder var trailing: () -> Trailing

    init(title: String, context: ShellContext, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.context = context
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: IslandSpacing.s) {
            Button { context.navigation.goHome() } label: {
                Label("Accueil", systemImage: "chevron.left")
                    .font(.islandCaptionEmphasis)
                    .foregroundStyle(IslandPalette.textSecondary.color)
            }
            .buttonStyle(HomeTapStyle())
            .help("Retour à l'accueil")
            Text(title)
                .font(.islandBodyEmphasis)
                .foregroundStyle(IslandPalette.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: IslandSpacing.s)
            trailing()
        }
        .frame(height: HomeGeometry.exploreHeader)
    }
}
