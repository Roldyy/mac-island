import IslandKit
import IslandUI
import SwiftUI

/// A feature's panel inside the island (Claude, clipboard, shelf...), under a back header.
/// The tab's own view is untouched; features that share a group get the sub-section picker.
struct HomePageView: View {
    let tabID: String
    let context: ShellContext

    private var tab: IslandTab? { context.tabs.first { $0.id == tabID } }

    private var siblings: [ShellSection] {
        guard let group = ShellLayout.group(containing: tabID) else { return [] }
        return ShellLayout.visibleSections(of: group) { context.registry.isEnabled($0) }
    }

    var body: some View {
        VStack(spacing: IslandSpacing.xs) {
            HomeBackHeader(title: tab?.title ?? "", context: context) { picker }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, IslandSpacing.l - 2)
        .padding(.bottom, IslandSpacing.s)
    }

    @ViewBuilder private var picker: some View {
        if siblings.count > 1 {
            Picker("Section", selection: Binding(
                get: { tabID },
                set: { context.navigation.open(tabID: $0) }
            )) {
                ForEach(siblings) { Text($0.title).tag($0.id) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)
        }
    }

    @ViewBuilder private var content: some View {
        if let tab, context.registry.isEnabled(tabID) {
            tab.makeView()
        } else {
            Text("Cet onglet est désactivé dans les Réglages.")
                .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
        }
    }
}
