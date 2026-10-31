import IslandUI
import SwiftUI

/// A round black button around the island. Right-click moves, reorders or removes it.
struct HomeCircleButton: View {
    let button: HomeButton
    let context: ShellContext

    var body: some View {
        if let action = HomeActionCatalog.action(button.actionID) {
            let available = context.isAvailable(action)
            let on = context.isOn(action)
            let title = button.label.isEmpty ? action.title : button.label
            Button { context.perform(action) } label: {
                ZStack {
                    Circle().fill(on ? IslandPalette.accent.color : IslandSurface.notchBlack)
                    Circle().strokeBorder(IslandPalette.textPrimary.color.opacity(0.14), lineWidth: 1)
                    Image(systemName: on ? action.activeSystemImage ?? action.systemImage : action.systemImage)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(on ? IslandSurface.notchBlack : IslandPalette.textPrimary.color)
                }
                .frame(width: HomeGeometry.circleDiameter, height: HomeGeometry.circleDiameter)
                .shadow(color: .black.opacity(0.45), radius: 5, y: 2)
                .contentShape(Circle())
            }
            .buttonStyle(HomeTapStyle())
            .disabled(!available)
            .help(available ? title : "\(title) : pas encore disponible")
            .accessibilityLabel(title)
            .accessibilityValue(action.activeSystemImage == nil ? "" : (on ? "activé" : "désactivé"))
            .contextMenu { menu }
        }
    }

    @ViewBuilder private var menu: some View {
        let layout = context.home.buttons
        let row = layout.buttons(on: button.side)
        let index = row.firstIndex { $0.id == button.id } ?? 0
        Button("Avancer", systemImage: "arrow.up") { context.home.buttons.reorder(id: button.id, by: -1) }
            .disabled(index == 0)
        Button("Reculer", systemImage: "arrow.down") { context.home.buttons.reorder(id: button.id, by: 1) }
            .disabled(index >= row.count - 1)
        Menu("Déplacer vers") {
            ForEach(HomeButtonSide.allCases.filter { $0 != button.side }, id: \.self) { side in
                Button(side.title) { context.home.buttons.move(id: button.id, to: side) }
                    .disabled(!layout.hasRoom(on: side))
            }
        }
        Divider()
        Button("Retirer ce bouton", systemImage: "minus.circle") { context.home.buttons.remove(id: button.id) }
    }
}
