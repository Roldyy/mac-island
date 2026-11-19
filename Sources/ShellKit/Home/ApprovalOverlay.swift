import AppKit
import ClaudeApproveCore
import ClaudeLiveKit
import IslandUI
import SwiftUI

/// The questions Claude Code is waiting on, on top of the open island. Each card shows the folder, the tool and ONE
/// line of what is asked, and offers Autoriser (only for a request the hook itself allows), Refuser and Ouvrir.
/// The closed island never shows this text (the screen may be shared): it only pulses.
struct ApprovalOverlay: View {
    let context: ShellContext
    private let store = ClaudeApprovalStore.shared
    private static let maxCards = 3

    var body: some View {
        let requests = store.requests
        if !requests.isEmpty {
            VStack(spacing: IslandSpacing.s) {
                ForEach(requests.prefix(Self.maxCards)) { request in
                    ApprovalCard(request: request,
                                 allow: { store.decide(request, .allow) },
                                 deny: { store.decide(request, .deny) },
                                 open: { open(request) })
                }
                if requests.count > Self.maxCards {
                    Text("+ \(requests.count - Self.maxCards) autre(s) demande(s) dans le terminal")
                        .font(.islandFootnote)
                        .foregroundStyle(IslandPalette.textSecondary.color)
                }
            }
            .padding(.horizontal, IslandSpacing.l)
            .frame(maxWidth: 460)
            .transition(.opacity)
        }
    }

    /// VS Code comes forward when the session says it runs there and the app is installed; otherwise the Agents tab opens.
    private func open(_ request: ClaudeApprovalRequest) {
        let entrypoint = ClaudeLiveMonitor.shared.sessions.first { $0.id == request.sessionID }?.entrypoint
        if let bundleID = ClaudeHostApp.bundleID(forEntrypoint: entrypoint),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } else {
            context.navigation.open(tabID: "agents")
        }
    }
}

struct ApprovalCard: View {
    let request: ClaudeApprovalRequest
    let allow: () -> Bool
    let deny: () -> Bool
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.s) {
            HStack(spacing: IslandSpacing.s) {
                Image(systemName: IslandStatus.warning.symbol)
                    .foregroundStyle(IslandStatus.warning.color)
                    .accessibilityHidden(true)
                Text(request.folderName.isEmpty ? "Claude demande" : "Claude demande · \(request.folderName)")
                    .font(.islandBodyEmphasis)
                    .foregroundStyle(IslandPalette.textPrimary.color)
                Spacer(minLength: 0)
                IslandBadge(request.tool)
            }
            Text(request.summary.isEmpty ? "Aucun détail à afficher" : request.summary)
                .font(.islandCaption)
                .foregroundStyle(IslandPalette.textSecondary.color)
                .lineLimit(4)
                .truncationMode(.middle)
            if !request.canAllow {
                Text(request.tier == .allow && !request.summaryComplete
                     ? "Trop longue pour être affichée en entier : décide dans Claude Code."
                     : "Trop sensible pour être autorisé ici : décide dans Claude Code.")
                    .font(.islandFootnote)
                    .foregroundStyle(IslandPalette.textSecondary.color)
            }
            HStack(spacing: IslandSpacing.s) {
                if request.canAllow {
                    Button("Autoriser") { _ = allow() }
                        .buttonStyle(IslandButtonStyle(.prominent))
                        .help("Autorise cette action une seule fois")
                }
                Button("Refuser") { _ = deny() }
                    .buttonStyle(IslandButtonStyle(.destructive))
                    .help("Refuse cette action")
                Button("Ouvrir") { open() }
                    .buttonStyle(IslandButtonStyle(.standard))
                    .help("Ouvre l'application de cette session")
                Spacer(minLength: 0)
            }
        }
        .padding(IslandSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .islandGlass(cornerRadius: IslandRadius.medium)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Claude demande une autorisation pour \(request.tool)")
    }
}
