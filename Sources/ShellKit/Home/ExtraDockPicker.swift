import IslandUI
import SwiftUI

/// The searchable list of every command of the app, opened by "+" in the extra dock. A command already in the dock is
/// ticked; a command that cannot run now stays listed, dimmed, with the reason under its name (it can still be added).
struct ExtraDockPicker: View {
    let context: ShellContext

    @State private var query = ""
    @FocusState private var searching: Bool

    var body: some View {
        let layout = context.home.extraDock
        let found = ExtraDockCatalog.search(context.dockCatalog(), query: query)
        VStack(alignment: .leading, spacing: IslandSpacing.s) {
            TextField("Rechercher une commande", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searching)
                .accessibilityLabel("Rechercher une commande")
            if found.isEmpty {
                IslandEmptyState(symbol: "magnifyingglass", message: "Aucune commande ne correspond.")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: IslandSpacing.xxs, pinnedViews: [.sectionHeaders]) {
                        ForEach(ExtraDockCatalog.grouped(found), id: \.category) { group in
                            Section {
                                ForEach(group.commands) { row($0, layout: layout) }
                            } header: {
                                Text(group.category.title)
                                    .font(.islandCaptionEmphasis).foregroundStyle(IslandPalette.textSecondary.color)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, IslandSpacing.xxs)
                                    .background(.thinMaterial)
                            }
                        }
                    }
                }
            }
            if layout.isFull {
                Text("L'extra-dock est plein : retire une commande pour en ajouter.")
                    .font(.islandCaption).foregroundStyle(IslandPalette.statusWarning.color)
            }
        }
        .padding(IslandSpacing.m)
        .frame(width: 320, height: 380)
        .onAppear { searching = true }
    }

    private func row(_ command: DockCommand, layout: ExtraDockLayout) -> some View {
        let inDock = layout.contains(command.id)
        let availability = context.dockAvailability(command)
        return Button {
            if inDock { context.home.extraDock.remove(command.id) } else { context.home.extraDock.add(command.id) }
        } label: {
            HStack(spacing: IslandSpacing.s) {
                Image(systemName: command.systemImage).frame(width: 22).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(command.title).font(.islandBody).lineLimit(1)
                    if let reason = availability.reason {
                        Text(reason).font(.islandFootnote).lineLimit(2)
                            .foregroundStyle(IslandPalette.textSecondary.color)
                    }
                }
                Spacer(minLength: IslandSpacing.xs)
                Image(systemName: inDock ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(inDock ? IslandPalette.accent.color : IslandPalette.textSecondary.color)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(IslandPalette.textPrimary.color)
            .opacity(availability.isAvailable ? 1 : 0.6)
            .padding(.vertical, IslandSpacing.xs)
            .padding(.horizontal, IslandSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!inDock && layout.isFull)
        .accessibilityLabel(command.title)
        .accessibilityValue(inDock ? "dans l'extra-dock" : "")
        .accessibilityHint(inDock ? "Retire du dock" : "Ajoute au dock")
    }
}
