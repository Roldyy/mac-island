import ClaudeLiveKit
import IslandUI
import SwiftUI

/// Live Claude sessions as one status bar: a header, then a chip per session (state dot, folder, the state
/// word when it matters). With no session the bar says so quietly instead of floating a lone chip.
struct AgentsSessionChips: View {
    let sessions: [ClaudeSession]
    let lastFinished: FinishedSession?
    static let limit = 4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: IslandSpacing.s) {
            Label(AgentsStrings.liveHeader, systemImage: AgentsCard.live.symbol)
                .font(.islandCaptionEmphasis).foregroundStyle(IslandStatus.info.color).lineLimit(1)
                .labelStyle(.titleAndIcon)
            if sessions.isEmpty {
                Text(AgentsStrings.text("noSession")).font(.islandCaption)
                    .foregroundStyle(IslandPalette.textSecondary.color).lineLimit(1)
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
        .padding(.horizontal, IslandSpacing.m)
        .frame(minHeight: 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IslandPalette.textPrimary.color.opacity(0.04), in: RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous)
            .strokeBorder(IslandPalette.separator.color.opacity(0.5), lineWidth: 0.5) }
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
                .lineLimit(1).truncationMode(.tail)
            if session.state == .working || session.state == .waiting {
                Text(AgentsLiveModel.cardLabel(for: session.state)).font(.islandFootnote).foregroundStyle(status.color).lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(session.folderName)
        .accessibilityValue(AgentsLiveModel.cardLabel(for: session.state))
    }

    private func chip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, IslandSpacing.s + 2).frame(minHeight: 24)
            .background(IslandPalette.textPrimary.color.opacity(0.08), in: Capsule())
            .overlay { Capsule().strokeBorder(IslandPalette.separator.color.opacity(0.5), lineWidth: 0.5) }
    }
}
