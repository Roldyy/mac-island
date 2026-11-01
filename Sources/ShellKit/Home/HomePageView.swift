import IslandKit
import IslandUI
import SwiftUI

/// A feature's panel inside the island (Claude, clipboard, shelf...), under a back header.
/// The tab's own view is untouched; one page per need, no sub-section switch.
struct HomePageView: View {
    let tabID: String
    let context: ShellContext

    private var tab: IslandTab? { context.tabs.first { $0.id == tabID } }

    var body: some View {
        VStack(spacing: IslandSpacing.xs) {
            HomeBackHeader(title: tab?.title ?? "", context: context)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, IslandSpacing.l - 2)
        .padding(.bottom, IslandSpacing.s)
    }

    @ViewBuilder private var content: some View {
        if let tab, context.isTabEnabled(tabID) {
            tab.makeView()
        } else {
            Text("Cet onglet est désactivé dans les Réglages.")
                .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
        }
    }
}
