import IslandUI
import SwiftUI

/// The "Pastilles d'état" page: the master switch, one switch per chip, and the order of the enabled ones (drag a
/// row onto another, or use the arrows). Everything writes `HomeModel`, which persists it and which the open island
/// already observes. Registered by the app delegate as the body of the `statuschips` page (`SettingsPageBodies`).
public struct StatusChipsSettings: View {
    public static let pageID = "statuschips"

    @Bindable var home: HomeModel

    public init(home: HomeModel) { self.home = home }

    public var body: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.l) {
            masterCard
            orderCard
            othersCard
        }
    }

    // MARK: - Master switch

    private var masterCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: IslandSpacing.xs) {
                Toggle("Afficher les pastilles d’état", isOn: $home.showsStatusChips).toggleStyle(IslandToggleStyle())
                caption("Une rangée sous le lecteur de l’île ouverte. Elle ne mesure rien tant que l’île est fermée.")
            }
        }
    }

    // MARK: - Enabled chips, in order

    private var orderCard: some View {
        let kinds = home.statusChipLayout.kinds
        return VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            IslandHeader("Affichées", subtitle: "Glissez une ligne sur une autre, ou utilisez les flèches, pour changer l’ordre.")
            SettingsCard {
                VStack(alignment: .leading, spacing: IslandSpacing.s) {
                    if kinds.isEmpty { caption("Aucune pastille affichée.") }
                    ForEach(kinds) { kind in
                        enabledRow(kind, count: kinds.count)
                        if kind != kinds.last { Divider() }
                    }
                    Divider()
                    Button("Rétablir les pastilles d’origine") { home.statusChipLayout = .initial }
                        .buttonStyle(IslandButtonStyle())
                        .disabled(home.statusChipLayout == .initial)
                }
                .disabled(!home.showsStatusChips)
            }
        }
    }

    private func enabledRow(_ kind: StatusChipKind, count: Int) -> some View {
        let index = home.statusChipLayout.kinds.firstIndex(of: kind) ?? 0
        return HStack(spacing: IslandSpacing.s) {
            row(kind, isOn: toggle(kind))
            Button("Monter", systemImage: "chevron.up") { home.statusChipLayout.reorder(kind, by: -1) }
                .labelStyle(.iconOnly).buttonStyle(.plain).disabled(index == 0)
            Button("Descendre", systemImage: "chevron.down") { home.statusChipLayout.reorder(kind, by: 1) }
                .labelStyle(.iconOnly).buttonStyle(.plain).disabled(index >= count - 1)
        }
        .contentShape(Rectangle())
        .draggable(StatusChipLayout.dragPayload(kind))
        .dropDestination(for: String.self) { items, _ in
            guard let moved = items.compactMap(StatusChipLayout.dragKind).first else { return false }
            home.statusChipLayout.move(moved, before: kind)
            return true
        }
    }

    // MARK: - Disabled chips

    private var othersCard: some View {
        let kinds = home.statusChipLayout.disabledKinds
        return VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            if !kinds.isEmpty {
                IslandHeader("Autres pastilles")
                SettingsCard {
                    VStack(alignment: .leading, spacing: IslandSpacing.s) {
                        ForEach(kinds) { kind in
                            row(kind, isOn: toggle(kind))
                            if kind != kinds.last { Divider() }
                        }
                    }
                    .disabled(!home.showsStatusChips)
                }
            }
        }
    }

    // MARK: - Pieces

    /// Title, one line of explanation and the switch. A chip with no source in this build says so and cannot be on.
    private func row(_ kind: StatusChipKind, isOn: Binding<Bool>) -> some View {
        let available = home.statusChips.availableKinds.contains(kind)
        return HStack(spacing: IslandSpacing.s) {
            Image(systemName: kind.symbol).frame(width: 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(kind.title).font(.islandBody)
                caption(available ? kind.summary : "Pas encore disponible dans cette version.")
            }
            Spacer()
            Toggle(kind.title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(IslandToggleStyle())
                .disabled(!available && !isOn.wrappedValue)
        }
    }

    /// The layout is a value with its own rules (`enable` / `disable`), so the switch reads and writes through them.
    private func toggle(_ kind: StatusChipKind) -> Binding<Bool> {
        Binding(get: { home.statusChipLayout.contains(kind) },
                set: { home.statusChipLayout.setEnabled(kind, $0) })
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
            .fixedSize(horizontal: false, vertical: true)
    }
}
