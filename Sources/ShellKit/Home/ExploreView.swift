import IslandUI
import SwiftUI

/// "Explorer": every shortcut of the home plus the hidden ones, in the same grid. A tap opens the panel in the island.
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

    /// The same tiles as the home (hidden ones too, marked, so they can be brought back), the same component.
    private var grid: some View {
        let items = context.tileItems(showHidden: true)
        let columns = context.home.tileColumns
        return HomeTileGrid(items: items, columns: columns,
                            visibleRows: HomeGeometry.exploreRows(itemCount: items.count, columns: columns), context: context)
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
