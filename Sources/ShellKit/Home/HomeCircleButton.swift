import IslandUI
import SwiftUI

/// A round black button around the island. Right-click moves, reorders or removes it.
///
/// A home action (the ids the layout always had) renders as before. Any other command of the app is a dock-catalog
/// command (`HomeDockCircleButton`): `dock` maps their ids to the commands, built once by the island.
struct HomeCircleButton: View {
    let button: HomeButton
    let context: ShellContext
    var dock: [String: DockCommand] = [:]

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
                    if HomeClaude.isClaude(action) {
                        ClaudeStatusDot().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
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
            .overlay(alignment: .bottomTrailing) {
                if HomeClaude.isClaude(action) { ClaudeOpenAppButton(context: context).offset(x: 5, y: 5) }
            }
            .contextMenu { HomeCircleMenu(button: button, context: context, isClaude: HomeClaude.isClaude(action)) }
        } else {
            HomeDockCircleButton(button: button, context: context,
                                 command: HomeActionCatalog.identity(of: button.actionID).flatMap { dock[$0] })
        }
    }
}

/// Right-click menu of a round button: move, reorder, remove. The Claude shortcut adds its "open the app" item.
struct HomeCircleMenu: View {
    let button: HomeButton
    let context: ShellContext
    var isClaude = false

    var body: some View {
        if isClaude {
            ClaudeOpenAppMenuItem(context: context)
            Divider()
        }

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
