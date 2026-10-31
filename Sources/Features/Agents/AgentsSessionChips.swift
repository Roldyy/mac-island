import ClaudeLiveKit
import IslandUI
import SwiftUI

/// Live Claude sessions as one row of compact chips: a state dot and the folder, the state word when it matters.
struct AgentsSessionChips: View {
    let sessions: [ClaudeSession]
    let lastFinished: FinishedSession?
    static let limit = 4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: IslandSpacing.s) {
            if sessions.isEmpty {
                chip { Text(AgentsStrings.text("noSession")).font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color) }
            }
            ForEach(sessions.prefix(Self.limit)) { session in chip { sessionLabel(session) } }
            if sessions.count > Self.limit {
                chip { Text("+\(sessions.count - Self.limit)").font(.islandCaptionEmphasis).monospacedDigit()
                    .foregroundStyle(IslandPalette.textSecondary.color) }
            }
            Spacer(minLength: 0)
            if let lastFinished {
                Label("\(lastFinished.folderName.isEmpty ? "—" : lastFinished.folderName) \(AgentsStrings.finishedChip)",
                      systemImage: "checkmark")
                    .font(.islandFootnote).foregroundStyle(IslandPalette.textTertiary.color).lineLimit(1)
            }
        }
        .frame(minHeight: 26)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AgentsCard.live.title)
    }

    private func sessionLabel(_ session: ClaudeSession) -> some View {
        let status = AgentsPage.status(session.state)
        return HStack(spacing: IslandSpacing.xs + 2) {
            Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(status.color)
                .symbolEffect(.pulse, options: .repeating, isActive: session.state == .working && !reduceMotion)
                .accessibilityHidden(true)
            Text(session.folderName.isEmpty ? "—" : session.folderName)
                .font(.islandCaptionEmphasis).foregroundStyle(IslandPalette.textPrimary.color)
                .lineLimit(1).truncationMode(.middle)
            if session.state == .working || session.state == .waiting {
                Text(AgentsLiveModel.cardLabel(for: session.state)).font(.islandFootnote).foregroundStyle(status.color)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(session.folderName)
        .accessibilityValue(AgentsLiveModel.cardLabel(for: session.state))
    }

    private func chip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, IslandSpacing.m).frame(minHeight: 26)
            .background(IslandPalette.textPrimary.color.opacity(0.08), in: Capsule())
            .overlay { Capsule().strokeBorder(IslandPalette.separator.color.opacity(0.5), lineWidth: 0.5) }
    }
}
