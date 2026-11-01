import IslandUI
import SwiftUI

/// The first thing on the page: two equal rings (the 5-hour session and the week) with their labels beside
/// them, or under them when the column is too narrow, never squeezed. Plan percentages come from the plan
/// file; a session with no fresh reading falls back to the log estimate (tokens, no percentage), exactly as
/// the limits state decides. One footer line carries the provenance (estimate, age of the reading).
struct AgentsHeroCard: View {
    let limits: LimitsState
    let display: AgentsLimitDisplay
    let now: Date
    /// The first snapshot has landed: an empty limits state then means "nothing yet", not "still loading".
    let isLoaded: Bool
    /// False in snapshots: the countdown then stays on `now`.
    var ticking = true

    static let ringSize: CGFloat = 96

    private var session: LimitRow? { limits.rows.first { $0.kind == .session } }
    private var week: LimitRow? { limits.rows.first { $0.kind == .weekly } }

    /// Color follows what is left, whichever way the figure is shown.
    static func tint(_ row: LimitRow) -> Color { row.level?.status.color ?? IslandPalette.accent.color }

    var body: some View {
        let tint = session.flatMap { $0.isPending ? nil : Self.tint($0) } ?? IslandPalette.accent.color
        VStack(alignment: .leading, spacing: IslandSpacing.m) {
            if limits.rows.isEmpty {
                HStack(alignment: .center, spacing: IslandSpacing.m) { placeholder }
            } else {
                // One decision for both rings: words beside them when both columns fit, under them otherwise.
                ViewThatFits(in: .horizontal) {
                    rings(stacked: false)
                    rings(stacked: true)
                }
            }
            footer
        }
        .padding(IslandSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .islandGlass(cornerRadius: IslandRadius.medium)
        .background(LinearGradient(colors: [tint.opacity(0.20), tint.opacity(0)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .clipShape(RoundedRectangle(cornerRadius: IslandRadius.medium, style: .continuous)))
        .opacity(limits.isStale ? 0.85 : 1)
        .islandAnimation(.easeInOut(duration: 0.35), value: limits.rows)
    }

    private func rings(stacked: Bool) -> some View {
        HStack(alignment: .center, spacing: IslandSpacing.m) {
            if let session { slot(session, stacked: stacked) { sessionColumn(session, stacked: stacked) } }
            if session != nil, week != nil {
                Rectangle().fill(IslandPalette.separator.color.opacity(0.5)).frame(width: 1, height: Self.ringSize)
            }
            if let week { slot(week, stacked: stacked) { weekColumn(week, stacked: stacked) } }
        }
    }

    /// A meter that cannot be told yet keeps its place and size as a placeholder; the real one fades in over it.
    @ViewBuilder
    private func slot<Content: View>(_ row: LimitRow, stacked: Bool, @ViewBuilder content: () -> Content) -> some View {
        Group {
            if row.isPending {
                pendingColumn(row, stacked: stacked)
            } else {
                content()
            }
        }
        .transition(.opacity)
        .frame(maxWidth: .infinity)
    }

    private func pendingColumn(_ row: LimitRow, stacked: Bool) -> some View {
        column(stacked: stacked,
               ring: Circle().stroke(IslandPalette.textPrimary.color.opacity(0.10), lineWidth: 10)
                   .frame(width: Self.ringSize, height: Self.ringSize).agentsShimmer()) { alignment in
            VStack(alignment: alignment, spacing: IslandSpacing.xs) {
                Text(row.title).font(.islandBodyEmphasis).foregroundStyle(IslandPalette.textPrimary.color).lineLimit(1)
                Text(AgentsStrings.computing).font(.islandCaptionEmphasis)
                    .foregroundStyle(IslandPalette.textSecondary.color).lineLimit(1)
                AgentsSkeletonBar(width: 120, height: 12)
                AgentsSkeletonBar(width: 90, height: 18)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.title)
        .accessibilityValue(AgentsStrings.computing)
    }

    // MARK: a ring and its words

    /// Ring beside its details when the column is wide enough for them on one line each, else the details under.
    @ViewBuilder
    private func column<Ring: View, Details: View>(stacked: Bool, ring: Ring,
                                                   @ViewBuilder details: (HorizontalAlignment) -> Details) -> some View {
        if stacked {
            VStack(spacing: IslandSpacing.s) { ring; details(.center) }.frame(maxWidth: .infinity)
        } else {
            HStack(spacing: IslandSpacing.m) { ring; details(.leading) }.frame(maxWidth: .infinity)
        }
    }

    // MARK: session

    private func sessionColumn(_ row: LimitRow, stacked: Bool) -> some View {
        let tint = Self.tint(row)
        return column(stacked: stacked, ring: ring(row, tint: tint, lineWidth: 10)) { alignment in
            VStack(alignment: alignment, spacing: IslandSpacing.xs) {
                Text(row.title).font(.islandBodyEmphasis).foregroundStyle(IslandPalette.textPrimary.color).lineLimit(1)
                if let level = row.level { levelLabel(level) }
                if row.isIdle {
                    Text(AgentsStrings.text("noSession")).font(.islandFootnote)
                        .foregroundStyle(IslandPalette.textTertiary.color).lineLimit(1)
                }
                countdown(row, alignment: alignment)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.title)
        .accessibilityValue([row.valueText(display), row.level?.label, row.renewal.map(renewalText)]
            .compactMap { $0 }.joined(separator: ", "))
    }

    private func ring(_ row: LimitRow, tint: Color, lineWidth: CGFloat) -> some View {
        AgentsGauge(fill: row.fill(display), tint: tint, pace: row.paceMarker(display), lineWidth: lineWidth) {
            ringCenter(row, tint: tint)
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
    }

    @ViewBuilder private func ringCenter(_ row: LimitRow, tint: Color) -> some View {
        if let fill = row.fill(display) {
            VStack(spacing: 0) {
                AgentsFigure(text: UsageFormat.percent(fill), font: .system(size: 24, weight: .bold, design: .rounded), color: tint)
                Text(AgentsStrings.text(display == .used ? "used" : "remaining").lowercased())
                    .font(.islandFootnote).foregroundStyle(IslandPalette.textSecondary.color)
            }
        } else if let tokens = row.tokens {
            VStack(spacing: 0) {
                AgentsFigure(text: UsageFormat.tokensShort(tokens), font: .system(size: 17, weight: .bold, design: .rounded), color: tint)
                Text(AgentsStrings.tokensShort).font(.islandFootnote).foregroundStyle(IslandPalette.textSecondary.color)
            }
            .padding(.horizontal, IslandSpacing.m)
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
    @ViewBuilder private func countdown(_ row: LimitRow, alignment: HorizontalAlignment) -> some View {
        if let renewal = row.renewal {
            if ticking {
                TimelineView(.periodic(from: now, by: 30)) { context in countdownBody(renewal, at: context.date, alignment: alignment) }
            } else {
                countdownBody(renewal, at: now, alignment: alignment)
            }
        }
    }

    private func countdownBody(_ renewal: Date, at date: Date, alignment: HorizontalAlignment) -> some View {
        let remaining = renewal.timeIntervalSince(date)
        return VStack(alignment: alignment, spacing: 0) {
            if remaining > 0 {
                Text(AgentsStrings.resetsIn).font(.islandFootnote).foregroundStyle(IslandPalette.textTertiary.color).lineLimit(1)
                AgentsFigure(text: UsageFormat.duration(remaining), font: .system(size: 18, weight: .semibold, design: .rounded))
            }
            Text("\(AgentsStrings.renewsAt) \(UsageFormat.clock(renewal))")
                .font(.islandFootnote).foregroundStyle(IslandPalette.textSecondary.color).lineLimit(1)
        }
    }

    private func renewalText(_ renewal: Date) -> String {
        let clock = "\(AgentsStrings.renewsAt) \(UsageFormat.clock(renewal))"
        let remaining = renewal.timeIntervalSince(now)
        guard remaining > 0 else { return clock }
        return "\(clock) · \(AgentsStrings.fill(constant: AgentsStrings.inFormat, UsageFormat.duration(remaining)))"
    }

    // MARK: week

    private func weekColumn(_ row: LimitRow, stacked: Bool) -> some View {
        let tint = Self.tint(row)
        return column(stacked: stacked, ring: ring(row, tint: tint, lineWidth: 10)) { alignment in
            VStack(alignment: alignment, spacing: IslandSpacing.xs) {
                Text(row.title).font(.islandBodyEmphasis).foregroundStyle(IslandPalette.textPrimary.color).lineLimit(1)
                if let level = row.level { levelLabel(level) }
                Text(AgentsStrings.overSevenDays).font(.islandFootnote)
                    .foregroundStyle(IslandPalette.textTertiary.color).lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.title)
        .accessibilityValue([row.valueText(display), row.level?.label].compactMap { $0 }.joined(separator: ", "))
    }

    // MARK: provenance

    /// Where the figures come from, as pills, and what the white tick means. Hidden when there is nothing to say.
    @ViewBuilder private var footer: some View {
        let pills = provenance
        let legend = tickLegend
        if !pills.isEmpty || legend != nil {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: IslandSpacing.s) {
                    pillRow(pills)
                    Spacer(minLength: IslandSpacing.s)
                    if let legend { legendText(legend) }
                }
                pillRow(pills).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private struct Provenance: Identifiable {
        var text: String
        var symbol: String
        var tint: Color
        var help: String?
        var id: String { text }
    }

    private var provenance: [Provenance] {
        var pills: [Provenance] = []
        if limits.source == .estimatedFromLogs {
            pills.append(Provenance(text: AgentsStrings.text("estimated"), symbol: "desktopcomputer", tint: IslandStatus.info.color,
                                    help: nil))
        } else if limits.hasEstimatedRow {
            pills.append(Provenance(text: AgentsStrings.text("estimated"), symbol: "desktopcomputer", tint: IslandStatus.info.color,
                                    help: AgentsStrings.sessionEstimatedNote))
        }
        if limits.source == .planFile, let date = limits.updated {
            let text = AgentsStrings.format("updatedFormat", UsageFormat.relative(date, now: now))
            pills.append(limits.isStale
                ? Provenance(text: text, symbol: IslandStatus.warning.symbol, tint: IslandStatus.warning.color, help: nil)
                : Provenance(text: text, symbol: "clock", tint: IslandPalette.textSecondary.color, help: nil))
        }
        return pills
    }

    private func pillRow(_ pills: [Provenance]) -> some View {
        HStack(spacing: IslandSpacing.s) {
            ForEach(pills) { pill in
                AgentsPill(text: pill.text, symbol: pill.symbol, tint: pill.tint).help(pill.help ?? pill.text)
            }
        }
    }

    /// The white tick is on the ring whenever the session knows how far its window has run.
    private var tickLegend: String? {
        guard let row = limits.rows.first(where: { $0.paceMarker(display) != nil }) else { return nil }
        return row.fill(display) == nil ? AgentsStrings.paceLegendElapsed : AgentsStrings.paceLegendShort
    }

    private func legendText(_ text: String) -> some View {
        HStack(spacing: IslandSpacing.xs) {
            Capsule().fill(IslandPalette.textPrimary.color).frame(width: 2.5, height: 11).accessibilityHidden(true)
            Text(text).font(.islandFootnote).foregroundStyle(IslandPalette.textTertiary.color).lineLimit(1)
        }
        .accessibilityHidden(true)
    }

    // MARK: nothing to show yet

    @ViewBuilder private var placeholder: some View {
        if isLoaded {
            HStack(spacing: IslandSpacing.m) {
                AgentsGauge(fill: nil, tint: IslandPalette.accent.color, lineWidth: 10) {
                    Text("—").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(IslandPalette.textSecondary.color)
                }
                .frame(width: Self.ringSize, height: Self.ringSize)
                AgentsNote(AgentsStrings.text("waitingForLimits")).frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            skeletonColumn
            Rectangle().fill(IslandPalette.separator.color.opacity(0.5)).frame(width: 1, height: Self.ringSize)
            skeletonColumn
        }
    }

    private var skeletonColumn: some View {
        HStack(spacing: IslandSpacing.m) {
            Circle().stroke(IslandPalette.textPrimary.color.opacity(0.10), lineWidth: 10)
                .frame(width: Self.ringSize, height: Self.ringSize).agentsShimmer()
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                AgentsSkeletonBar(width: 70, height: 14)
                AgentsSkeletonBar(width: 90, height: 12)
                AgentsSkeletonBar(width: 60, height: 20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}
