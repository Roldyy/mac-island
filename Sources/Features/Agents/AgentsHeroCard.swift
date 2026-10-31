import IslandUI
import SwiftUI

/// The first thing on the page: a big ring for the 5-hour session, a smaller one for the week, and how long
/// until the session renews. Plan percentages come from the plan file; a session with no fresh reading falls
/// back to the log estimate (tokens, no percentage), exactly as the limits state decides.
struct AgentsHeroCard: View {
    let limits: LimitsState
    let display: AgentsLimitDisplay
    let now: Date
    /// The first snapshot has landed: an empty limits state then means "nothing yet", not "still loading".
    let isLoaded: Bool
    /// False in snapshots: the countdown then stays on `now`.
    var ticking = true

    private var session: LimitRow? { limits.rows.first { $0.kind == .session } }
    private var week: LimitRow? { limits.rows.first { $0.kind == .weekly } }

    /// Color follows what is left, whichever way the figure is shown.
    static func tint(_ row: LimitRow) -> Color { row.level?.status.color ?? IslandPalette.accent.color }

    var body: some View {
        let tint = session.map(Self.tint) ?? IslandPalette.accent.color
        HStack(alignment: .center, spacing: IslandSpacing.l) {
            if limits.rows.isEmpty {
                placeholder
            } else {
                if let session { sessionPart(session) }
                if let week {
                    Rectangle().fill(IslandPalette.separator.color.opacity(0.5)).frame(width: 1)
                    weekPart(week)
                }
            }
        }
        .padding(IslandSpacing.m)
        .frame(maxWidth: .infinity, minHeight: 140, maxHeight: .infinity, alignment: .leading)
        .islandGlass(cornerRadius: IslandRadius.medium)
        .background(LinearGradient(colors: [tint.opacity(0.20), tint.opacity(0)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .clipShape(RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous)))
        .opacity(limits.isStale ? 0.85 : 1)
    }

    // MARK: session

    private func sessionPart(_ row: LimitRow) -> some View {
        let tint = Self.tint(row)
        return HStack(alignment: .center, spacing: IslandSpacing.l) {
            AgentsGauge(fill: row.fill(display), tint: tint, pace: row.paceMarker(display), lineWidth: 10) {
                ringCenter(row, tint: tint)
            }
            .frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: IslandSpacing.xs) {
                HStack(spacing: IslandSpacing.s) {
                    Text(row.title).font(.islandBodyEmphasis).foregroundStyle(IslandPalette.textPrimary.color)
                    if let level = row.level { levelLabel(level) }
                }
                countdown(row)
                notes
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.title)
        .accessibilityValue([row.valueText(display), row.level?.label, row.renewal.map(renewalText)]
            .compactMap { $0 }.joined(separator: ", "))
    }

    @ViewBuilder private func ringCenter(_ row: LimitRow, tint: Color) -> some View {
        if let fill = row.fill(display) {
            VStack(spacing: 0) {
                AgentsFigure(text: UsageFormat.percent(fill), font: .system(size: 27, weight: .bold, design: .rounded), color: tint)
                Text(AgentsStrings.text(display == .used ? "used" : "remaining").lowercased())
                    .font(.islandFootnote).foregroundStyle(IslandPalette.textSecondary.color)
            }
        } else if let tokens = row.tokens {
            VStack(spacing: 0) {
                AgentsFigure(text: UsageFormat.tokens(tokens), font: .system(size: 20, weight: .bold, design: .rounded), color: tint)
                Text(AgentsStrings.tokensShort).font(.islandFootnote).foregroundStyle(IslandPalette.textSecondary.color)
            }
        } else {
            Text("—").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(IslandPalette.textSecondary.color)
        }
    }

    private func levelLabel(_ level: LimitLevel) -> some View {
        Label(level.label, systemImage: level.status.symbol)
            .font(.islandCaptionEmphasis)
            .foregroundStyle(level.status.color)
            .lineLimit(1)
    }

    /// "Se renouvelle dans 2 h 13 min", ticking every 30 s while the page is live.
    @ViewBuilder private func countdown(_ row: LimitRow) -> some View {
        if let renewal = row.renewal {
            if ticking {
                TimelineView(.periodic(from: now, by: 30)) { context in countdownBody(renewal, at: context.date) }
            } else {
                countdownBody(renewal, at: now)
            }
        }
    }

    private func countdownBody(_ renewal: Date, at date: Date) -> some View {
        let remaining = renewal.timeIntervalSince(date)
        return VStack(alignment: .leading, spacing: 0) {
            if remaining > 0 {
                Text(AgentsStrings.resetsIn).font(.islandFootnote).foregroundStyle(IslandPalette.textTertiary.color)
                AgentsFigure(text: UsageFormat.duration(remaining), font: .system(size: 21, weight: .semibold, design: .rounded))
            }
            Text("\(AgentsStrings.renewsAt) \(UsageFormat.clock(renewal))")
                .font(.islandCaption).foregroundStyle(IslandPalette.textSecondary.color)
        }
    }

    private func renewalText(_ renewal: Date) -> String {
        let clock = "\(AgentsStrings.renewsAt) \(UsageFormat.clock(renewal))"
        let remaining = renewal.timeIntervalSince(now)
        guard remaining > 0 else { return clock }
        return "\(clock) · \(AgentsStrings.fill(constant: AgentsStrings.inFormat, UsageFormat.duration(remaining)))"
    }

    @ViewBuilder private var notes: some View {
        if limits.source == .estimatedFromLogs {
            AgentsNote(AgentsStrings.text("estimated"))
        } else if limits.hasEstimatedRow {
            AgentsNote(AgentsStrings.sessionEstimatedNote).lineLimit(3)
        }
        if limits.source == .planFile, let date = limits.updated {
            if limits.isStale {
                Label(AgentsStrings.format("updatedFormat", UsageFormat.relative(date, now: now)), systemImage: IslandStatus.warning.symbol)
                    .font(.islandFootnote).foregroundStyle(IslandStatus.warning.color)
            } else {
                AgentsNote(AgentsStrings.format("updatedFormat", UsageFormat.relative(date, now: now)))
            }
        }
    }

    // MARK: week

    private func weekPart(_ row: LimitRow) -> some View {
        let tint = Self.tint(row)
        return VStack(spacing: IslandSpacing.xs) {
            AgentsGauge(fill: row.fill(display), tint: tint, pace: row.paceMarker(display), lineWidth: 8) {
                if let fill = row.fill(display) {
                    VStack(spacing: 0) {
                        AgentsFigure(text: UsageFormat.percent(fill), font: .system(size: 15, weight: .bold, design: .rounded), color: tint)
                        Text(AgentsStrings.text(display == .used ? "used" : "remaining").lowercased())
                            .font(.islandFootnote).foregroundStyle(IslandPalette.textSecondary.color)
                    }
                } else if let tokens = row.tokens {
                    AgentsFigure(text: UsageFormat.tokens(tokens), font: .system(size: 12, weight: .bold, design: .rounded), color: tint)
                }
            }
            .frame(width: 70, height: 70)
            Text(row.title).font(.islandBodyEmphasis).foregroundStyle(IslandPalette.textPrimary.color)
            if let level = row.level {
                // Word only: the ring's color and percentage already carry the rest, and the column is narrow.
                Text(level.label).font(.islandCaptionEmphasis).foregroundStyle(level.status.color)
                    .lineLimit(2).multilineTextAlignment(.center)
            }
        }
        .frame(width: 104)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.title)
        .accessibilityValue([row.valueText(display), row.level?.label].compactMap { $0 }.joined(separator: ", "))
    }

    // MARK: nothing to show yet

    @ViewBuilder private var placeholder: some View {
        if isLoaded {
            AgentsGauge(fill: nil, tint: IslandPalette.accent.color, lineWidth: 10) {
                Text("—").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(IslandPalette.textSecondary.color)
            }
            .frame(width: 104, height: 104)
            AgentsNote(AgentsStrings.text("waitingForLimits")).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Circle().stroke(IslandPalette.textPrimary.color.opacity(0.10), lineWidth: 10)
                .frame(width: 104, height: 104).agentsShimmer()
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                AgentsSkeletonBar(width: 90, height: 14)
                AgentsSkeletonBar(width: 140, height: 24)
                AgentsSkeletonBar(width: 110, height: 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
            Rectangle().fill(IslandPalette.separator.color.opacity(0.5)).frame(width: 1)
            VStack(spacing: IslandSpacing.xs) {
                Circle().stroke(IslandPalette.textPrimary.color.opacity(0.10), lineWidth: 8)
                    .frame(width: 70, height: 70).agentsShimmer()
                AgentsSkeletonBar(width: 60, height: 12)
            }
            .frame(width: 100)
            .accessibilityHidden(true)
        }
    }
}
