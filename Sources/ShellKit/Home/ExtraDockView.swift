import IslandUI
import SwiftUI

/// The extra dock: a pinned frosted row on the home, between the now-playing card and the grid. Each button runs one
/// command of the app (`ShellContext.dockCatalog()`); the user adds, removes and reorders them.
///
/// - "+" opens the searchable picker. The pencil switches the edit mode: a "-" badge on each button removes it and
///   a button can be dragged to a new place (no jiggle, no animation beyond a fade).
/// - Right-click on a button: Avancer, Reculer, Retirer, in or out of the edit mode.
/// - A command that changes or discards something shows its question in the row first ("Confirmer" / "Annuler").
/// - The row never grows: the buttons scroll sideways when they do not all fit.
struct ExtraDockView: View {
    let context: ShellContext

    @State private var editing = false
    @State private var picking = false
    /// The command waiting for its "Confirmer" click.
    @State private var pending: DockCommand?
    /// Bumped after a command ran, so a toggle that lives outside Observation (the mic) shows its new state.
    @State private var revision = 0

    static let buttonSize: CGFloat = 32

    var body: some View {
        let home = context.home
        let _ = revision
        let commands = context.dockCommands(for: home.extraDock)
        HStack(spacing: IslandSpacing.xs) {
            if let pending {
                confirmation(for: pending)
            } else {
                buttons(commands)
                controls
            }
        }
        .padding(.horizontal, IslandSpacing.s)
        .frame(maxWidth: .infinity)
        .frame(height: HomeGeometry.extraDockRow)
        .islandGlass(cornerRadius: IslandRadius.medium)
        .islandAnimation(.easeOut(duration: 0.12), value: home.extraDock.ids)
        .islandAnimation(.easeOut(duration: 0.12), value: pending?.id)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Extra-dock")
    }

    // MARK: - Buttons

    @ViewBuilder private func buttons(_ commands: [DockCommand]) -> some View {
        if commands.isEmpty {
            Text("Ajoute des commandes avec +")
                .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: IslandSpacing.xs) {
                    ForEach(commands) { command in
                        ExtraDockButton(command: command, context: context, editing: editing,
                                        run: run, remove: { context.home.extraDock.remove(command.id) })
                            .contextMenu { menu(for: command) }
                            .modifier(DockReorder(id: command.id, editing: editing) { moved, target in
                                context.home.extraDock.move(moved, before: target)
                            })
                    }
                }
                .padding(.vertical, IslandSpacing.xxs)
            }
            .scrollIndicators(.never)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var controls: some View {
        HStack(spacing: IslandSpacing.xxs) {
            Button { picking = true } label: { glyph("plus") }
                .buttonStyle(HomeTapStyle())
                .disabled(context.home.extraDock.isFull)
                .help(context.home.extraDock.isFull ? "L'extra-dock est plein (\(ExtraDockLayout.maxItems) commandes)" : "Ajouter une commande")
                .accessibilityLabel("Ajouter une commande à l'extra-dock")
                .popover(isPresented: $picking, arrowEdge: .bottom) { ExtraDockPicker(context: context) }
                // Dropping a button on "+" sends it to the end of the row.
                .modifier(DockEndDrop(editing: editing) { context.home.extraDock.move($0, before: nil) })
            Button { editing.toggle() } label: { glyph(editing ? "checkmark" : "pencil") }
                .buttonStyle(HomeTapStyle())
                .help(editing ? "Terminer la modification" : "Modifier l'extra-dock")
                .accessibilityLabel(editing ? "Terminer la modification de l'extra-dock" : "Modifier l'extra-dock")
        }
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(IslandPalette.textPrimary.color)
            .frame(width: 26, height: Self.buttonSize)
            .contentShape(Rectangle())
    }

    @ViewBuilder private func menu(for command: DockCommand) -> some View {
        let ids = context.home.extraDock.ids
        let index = ids.firstIndex(of: command.id) ?? 0
        Button("Avancer", systemImage: "arrow.left") { context.home.extraDock.reorder(command.id, by: -1) }
            .disabled(index == 0)
        Button("Reculer", systemImage: "arrow.right") { context.home.extraDock.reorder(command.id, by: 1) }
            .disabled(index >= ids.count - 1)
        Divider()
        Button("Retirer de l'extra-dock", systemImage: "minus.circle") { context.home.extraDock.remove(command.id) }
    }

    // MARK: - Run, confirm

    private func run(_ command: DockCommand) {
        if command.needsConfirmation { pending = command } else { perform(command) }
    }

    private func perform(_ command: DockCommand) {
        context.performDock(command)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            revision += 1
        }
    }

    private func confirmation(for command: DockCommand) -> some View {
        HStack(spacing: IslandSpacing.s) {
            Text(command.confirmation ?? "")
                .font(.islandCaption).foregroundStyle(IslandPalette.textPrimary.color)
                .lineLimit(2).minimumScaleFactor(0.9)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Annuler") { pending = nil }.buttonStyle(IslandButtonStyle())
            Button("Confirmer") {
                pending = nil
                perform(command)
            }
            .buttonStyle(IslandButtonStyle(.destructive))
            .keyboardShortcut(.defaultAction)
        }
        .accessibilityElement(children: .contain)
    }
}

/// One button of the dock: glyph in a round chip, filled while a toggle is on, dimmed with its reason when disabled.
struct ExtraDockButton: View {
    let command: DockCommand
    let context: ShellContext
    let editing: Bool
    let run: (DockCommand) -> Void
    let remove: () -> Void

    var body: some View {
        let availability = context.dockAvailability(command)
        let on = command.isOn?() == true
        Button { if !editing { run(command) } } label: {
            ZStack {
                Circle().fill(on ? IslandPalette.accent.color : IslandPalette.textPrimary.color.opacity(0.10))
                Image(systemName: on ? command.activeSystemImage ?? command.systemImage : command.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(on ? IslandSurface.notchBlack : IslandPalette.textPrimary.color)
            }
            .frame(width: ExtraDockView.buttonSize, height: ExtraDockView.buttonSize)
            .opacity(availability.isAvailable ? 1 : 0.4)
            .contentShape(Circle())
        }
        .buttonStyle(HomeTapStyle())
        .disabled(!availability.isAvailable && !editing)
        .help(availability.reason.map { "\(command.title) : \($0)" } ?? command.title)
        .accessibilityLabel(availability.isAvailable ? command.title : "\(command.title), indisponible")
        .accessibilityValue(command.isOn == nil ? "" : (on ? "activé" : "désactivé"))
        .overlay(alignment: .topTrailing) {
            if editing {
                Button(action: remove) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 13))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(IslandPalette.onFill.color, IslandPalette.destructiveFill.color)
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .help("Retirer \(command.title)")
                .accessibilityLabel("Retirer \(command.title) de l'extra-dock")
            }
        }
    }
}

/// Drag a button onto another to take its place. Active only in the edit mode.
private struct DockReorder: ViewModifier {
    let id: String
    let editing: Bool
    let move: (_ id: String, _ before: String) -> Void

    func body(content: Content) -> some View {
        if editing {
            content
                .draggable(ExtraDockLayout.dragPayload(id))
                .dropDestination(for: String.self) { items, _ in
                    guard let moved = items.compactMap(ExtraDockLayout.dragID).first else { return false }
                    move(moved, id)
                    return true
                }
        } else {
            content
        }
    }
}

/// Drop target after the last button (the "+" control).
private struct DockEndDrop: ViewModifier {
    let editing: Bool
    let move: (_ id: String) -> Void

    func body(content: Content) -> some View {
        if editing {
            content.dropDestination(for: String.self) { items, _ in
                guard let moved = items.compactMap(ExtraDockLayout.dragID).first else { return false }
                move(moved)
                return true
            }
        } else {
            content
        }
    }
}
