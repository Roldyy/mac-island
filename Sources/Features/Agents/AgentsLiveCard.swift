import ClaudeLiveKit
import IslandUI
import SwiftUI

struct AgentsLiveCard: View {
    let sessions: [ClaudeSession]
    let lastFinished: FinishedSession?
    var now = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AgentsCardFrame(.live, trailing: { count }) {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                if sessions.isEmpty {
                    Text(AgentsStrings.text("noSession")).font(.islandBody)
                        .foregroundStyle(IslandPalette.textSecondary.color)
                }
                ForEach(sessions) { session in
                    HStack(spacing: IslandSpacing.s) {
                        glyph(session.state)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(session.folderName.isEmpty ? "—" : session.folderName)
                                .font(.islandBodyEmphasis).foregroundStyle(IslandPalette.textPrimary.color)
                                .lineLimit(1).truncationMode(.middle)
                            if let detail = detail(session) {
                                Text(detail).font(.islandFootnote).foregroundStyle(IslandPalette.textTertiary.color)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: IslandSpacing.xs)
                        Text(AgentsLiveModel.cardLabel(for: session.state))
                            .font(.islandCaptionEmphasis)
                            .foregroundStyle(session.state == .working ? IslandStatus.info.color
                                             : session.state == .waiting ? IslandStatus.warning.color
                                             : IslandPalette.textSecondary.color)
                    }
                    .padding(.vertical, IslandSpacing.xxs)
                    .accessibilityElement(children: .combine)
                }
                if let lastFinished {
                    AgentsNote(AgentsStrings.format("finishedFormat", lastFinished.folderName.isEmpty ? "—" : lastFinished.folderName))
                }
            }
        }
    }

    /// "VS Code · depuis 4 min": where it runs and how long it has been in this state.
    private func detail(_ session: ClaudeSession) -> String? {
        let place: String? = switch session.entrypoint {
        case "cli": "Terminal"
        case "claude-vscode": "VS Code"
        case let other?: other
        case nil: nil
        }
        let since = session.updatedAt.map { "depuis \(UsageFormat.duration(now.timeIntervalSince($0)))" }
        let parts = [place, since].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder private var count: some View {
        if !sessions.isEmpty {
            Text("\(sessions.count)")
                .font(.islandCaptionEmphasis).monospacedDigit()
                .foregroundStyle(IslandPalette.textPrimary.color)
                .padding(.horizontal, IslandSpacing.s).padding(.vertical, 1)
                .background(IslandPalette.textPrimary.color.opacity(0.14), in: Capsule())
                .accessibilityHidden(true)
        }
    }

    /// Working pulses; Reduce Motion keeps the glyph still (the status symbol carries the meaning).
    private func glyph(_ state: ClaudeSession.State) -> some View {
        let status = AgentsPage.status(state)
        return Image(systemName: state == .working ? "circle.fill" : status.symbol)
            .font(.islandBody)
            .foregroundStyle(status.color)
            .symbolEffect(.pulse, options: .repeating, isActive: state == .working && !reduceMotion)
            .accessibilityHidden(true)
    }
}
