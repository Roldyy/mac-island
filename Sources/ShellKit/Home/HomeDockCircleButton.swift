import IslandUI
import SwiftUI

/// A round button that runs any command of the app (`ShellContext.dockCatalog()`): same face, shadow and tap style as
/// the home actions, with what the catalog adds. A toggle shows its state, a command that cannot run now is dimmed
/// with its reason as the tooltip, and one that changes or discards something asks first in a small popover.
/// A command the catalog does not list right now (an app command registered late, another build) keeps its place as a
/// dimmed "?" button the user can still move or remove: a stored layout is never trimmed by what is missing today.
struct HomeDockCircleButton: View {
    let button: HomeButton
    let context: ShellContext
    let command: DockCommand?

    @State private var confirming = false
    /// Bumped after a command ran, so a toggle that lives outside Observation (the mic) shows its new state.
    @State private var revision = 0

    var body: some View {
        let _ = revision
        let availability = command.map { context.dockAvailability($0) }
        let usable = availability?.isAvailable == true
        let on = command?.isOn?() == true
        let title = button.label.isEmpty ? (command?.title ?? "Commande introuvable") : button.label
        let symbol = command.map { on ? $0.activeSystemImage ?? $0.systemImage : $0.systemImage } ?? "questionmark"
        Button { run() } label: {
            ZStack {
                Circle().fill(on ? IslandPalette.accent.color : IslandSurface.notchBlack)
                Circle().strokeBorder(IslandPalette.textPrimary.color.opacity(0.14), lineWidth: 1)
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(on ? IslandSurface.notchBlack : IslandPalette.textPrimary.color)
            }
            .frame(width: HomeGeometry.circleDiameter, height: HomeGeometry.circleDiameter)
            .opacity(usable ? 1 : 0.5)
            .shadow(color: .black.opacity(0.45), radius: 5, y: 2)
            .contentShape(Circle())
        }
        .buttonStyle(HomeTapStyle())
        .disabled(!usable)
        .help(Self.help(title: title, command: command, reason: availability?.reason, id: button.actionID))
        .accessibilityLabel(usable ? title : "\(title), indisponible")
        .accessibilityValue(command?.isOn == nil ? "" : (on ? "activé" : "désactivé"))
        .popover(isPresented: $confirming, arrowEdge: .bottom) {
            if let command { confirmation(for: command) }
        }
        .contextMenu { HomeCircleMenu(button: button, context: context) }
    }

    /// The tooltip keeps the title; a disabled command adds its reason.
    static func help(title: String, command: DockCommand?, reason: String?, id: String) -> String {
        guard command != nil else { return "\(title) : \(id)" }
        return reason.map { "\(title) : \($0)" } ?? title
    }

    private func run() {
        guard let command else { return }
        if command.needsConfirmation { confirming = true } else { perform(command) }
    }

    private func perform(_ command: DockCommand) {
        context.performDock(command)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            revision += 1
        }
    }

    private func confirmation(for command: DockCommand) -> some View {
        VStack(alignment: .leading, spacing: IslandSpacing.s) {
            Text(command.confirmation ?? "")
                .font(.islandCaption).foregroundStyle(IslandPalette.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: IslandSpacing.s) {
                Spacer(minLength: 0)
                Button("Annuler") { confirming = false }.buttonStyle(IslandButtonStyle())
                Button("Confirmer") {
                    confirming = false
                    perform(command)
                }
                .buttonStyle(IslandButtonStyle(.destructive))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(IslandSpacing.m)
        .frame(width: 260)
        .accessibilityElement(children: .contain)
    }
}
