import ClaudeLiveKit
import IslandUI
import SwiftUI

struct AgentsLiveCard: View {
    let sessions: [ClaudeSession]
    let lastFinished: FinishedSession?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AgentsCardFrame(.live) {
            VStack(alignment: .leading, spacing: IslandSpacing.xs) {
                if sessions.isEmpty {
                    Text(AgentsStrings.text("noSession")).font(.islandCaption)
                        .foregroundStyle(IslandPalette.textSecondary.color)
                }
                ForEach(sessions) { session in
                    HStack(spacing: IslandSpacing.xs) {
                        glyph(session.state)
                        Text(session.folderName.isEmpty ? "—" : session.folderName)
                            .font(.islandCaption).foregroundStyle(IslandPalette.textPrimary.color)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: IslandSpacing.xs)
                        Text(AgentsLiveModel.cardLabel(for: session.state))
                            .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let lastFinished {
                    AgentsNote(AgentsStrings.format("finishedFormat", lastFinished.folderName.isEmpty ? "—" : lastFinished.folderName))
                }
            }
        }
    }

    /// Working pulses; Reduce Motion keeps the glyph still (the status symbol carries the meaning).
    private func glyph(_ state: ClaudeSession.State) -> some View {
        let status = AgentsTabView.status(state)
        return Image(systemName: state == .working ? "circle.fill" : status.symbol)
            .font(.islandCaption)
            .foregroundStyle(status.color)
            .symbolEffect(.pulse, options: .repeating, isActive: state == .working && !reduceMotion)
            .accessibilityHidden(true)
    }
}
