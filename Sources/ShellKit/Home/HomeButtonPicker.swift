import IslandUI
import SwiftUI

/// The searchable list of every command of the app a round button can run: the extra dock's catalog, grouped by
/// category. Commands already shown as a round button are left out (one action, one button). A command that cannot run
/// now stays listed, dimmed, with its reason under the name: it can still be added and will wake up when it can.
struct HomeButtonPicker: View {
    let catalog: [DockCommand]
    let layout: HomeButtonLayout
    let side: HomeButtonSide
    let availability: (DockCommand) -> DockAvailability
    let add: (String) -> Void

    @State private var query = ""
    @FocusState private var searching: Bool

    var body: some View {
        let free = HomeButtonPicker.candidates(catalog, layout: layout)
        let found = ExtraDockCatalog.search(free, query: query)
        VStack(alignment: .leading, spacing: IslandSpacing.s) {
            TextField("Rechercher une commande", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searching)
                .accessibilityLabel("Rechercher une commande")
            if found.isEmpty {
                IslandEmptyState(symbol: "magnifyingglass",
                                 message: free.isEmpty ? "Toutes les commandes ont déjà leur bouton." : "Aucune commande ne correspond.")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: IslandSpacing.xxs, pinnedViews: [.sectionHeaders]) {
                        ForEach(ExtraDockCatalog.grouped(found), id: \.category) { group in
                            Section {
                                ForEach(group.commands) { row($0) }
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
            if !layout.hasRoom(on: side) {
                Text("\(side.title) est plein : retire un bouton pour en ajouter.")
                    .font(.islandCaption).foregroundStyle(IslandPalette.statusWarning.color)
            }
        }
        .padding(IslandSpacing.m)
        .frame(width: 320, height: 380)
        .onAppear { searching = true }
    }

    /// What the picker offers: every command no round button shows yet, in the catalog's order.
    static func candidates(_ catalog: [DockCommand], layout: HomeButtonLayout) -> [DockCommand] {
        catalog.filter { !layout.contains(actionID: $0.id) }
    }

    private func row(_ command: DockCommand) -> some View {
        let state = availability(command)
        return Button { add(command.id) } label: {
            HStack(spacing: IslandSpacing.s) {
                Image(systemName: command.systemImage).frame(width: 22).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(command.title).font(.islandBody).lineLimit(1)
                    if let reason = state.reason {
                        Text(reason).font(.islandFootnote).lineLimit(2)
                            .foregroundStyle(IslandPalette.textSecondary.color)
                    }
                    if command.needsConfirmation {
                        Text("Demande une confirmation").font(.islandFootnote)
                            .foregroundStyle(IslandPalette.textSecondary.color)
                    }
                }
                Spacer(minLength: IslandSpacing.xs)
                Image(systemName: "plus.circle").foregroundStyle(IslandPalette.textSecondary.color)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(IslandPalette.textPrimary.color)
            .opacity(state.isAvailable ? 1 : 0.6)
            .padding(.vertical, IslandSpacing.xs)
            .padding(.horizontal, IslandSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!layout.hasRoom(on: side))
        .accessibilityLabel(command.title)
        .accessibilityHint("Ajoute un bouton \(side.title.lowercased())")
    }
}
