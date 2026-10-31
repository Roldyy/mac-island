import IslandKit
import IslandUI
import SwiftUI

/// Which home action carries the Claude extras (status dot, "Ouvrir Claude").
enum HomeClaude {
    static let actionID = "agents"
    static func isClaude(_ action: HomeAction) -> Bool { action.id == actionID }
}

/// Small dot on the Claude shortcut while a session works or waits. The shape differs too (dot or raised
/// hand): colour is never the only signal. Nothing is drawn while idle.
struct ClaudeStatusDot: View {
    @ObservedObject var center: ActivityCenter = .shared

    var body: some View {
        let status = ClaudeHomeStatus.from(layout: center.layout)
        if let label = status.label {
            ZStack {
                Circle().fill(IslandSurface.notchBlack)
                Image(systemName: status == .waiting ? "hand.raised.fill" : "circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(status == .waiting ? IslandStatus.warning.color : IslandStatus.info.color)
            }
            .frame(width: 19, height: 19)
            .help(label)
            .accessibilityLabel(label)
        }
    }
}

/// The second affordance of the Claude shortcut: a small button that launches the Claude desktop app.
/// Disabled, with its reason in the tooltip, when `/Applications/Claude.app` does not exist.
struct ClaudeOpenAppButton: View {
    let context: ShellContext

    var body: some View {
        let launcher = context.home.claudeApp
        let reason = launcher.unavailableReason
        Button { launcher.launch() } label: {
            ZStack {
                Circle().fill(IslandSurface.notchBlack)
                Circle().strokeBorder(IslandPalette.textPrimary.color.opacity(0.3), lineWidth: 1)
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(IslandPalette.textPrimary.color)
            }
            .frame(width: 21, height: 21)
            .contentShape(Circle().inset(by: -3))
        }
        .buttonStyle(HomeTapStyle())
        .disabled(reason != nil)
        .help(reason.map { "Ouvrir Claude : \($0)" } ?? "Ouvrir l'app Claude")
        .accessibilityLabel("Ouvrir Claude")
    }
}

/// Right-click item of the Claude shortcut (round button and tile).
struct ClaudeOpenAppMenuItem: View {
    let context: ShellContext

    var body: some View {
        let launcher = context.home.claudeApp
        Button(launcher.isAvailable ? "Ouvrir Claude" : "Ouvrir Claude (Claude.app introuvable)",
               systemImage: "arrow.up.forward.app") { launcher.launch() }
            .disabled(!launcher.isAvailable)
    }
}
