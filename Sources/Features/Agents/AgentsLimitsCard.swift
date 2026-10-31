import IslandUI
import SwiftUI

/// The first thing on the page: how much of each plan limit is left. Big figure, word + symbol for the
/// level (green above 50 % left, orange 20 to 50, red under 20), meter with its pace marker.
struct AgentsLimitsCard: View {
    let limits: LimitsState
    let display: AgentsLimitDisplay
    var now = Date()

    var body: some View {
        AgentsCardFrame(.limits, trailing: { updated }) {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                if limits.rows.isEmpty {
                    AgentsNote(AgentsStrings.text("waitingForLimits"))
                } else {
                    HStack(alignment: .top, spacing: IslandSpacing.l) {
                        ForEach(Array(limits.rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 {
                                Rectangle().fill(IslandPalette.separator.color.opacity(0.5)).frame(width: 1)
                            }
                            panel(row)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                footer
            }
        }
    }

    // MARK: one limit

    private func panel(_ row: LimitRow) -> some View {
        let tint = Self.tint(row)
        return VStack(alignment: .leading, spacing: IslandSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: IslandSpacing.xs) {
                Text(row.title).font(.islandBodyEmphasis).foregroundStyle(IslandPalette.textPrimary.color)
                Spacer(minLength: IslandSpacing.xs)
                if let level = row.level {
                    Label(level.label, systemImage: level.status.symbol)
                        .font(.islandCaptionEmphasis)
                        .foregroundStyle(level.status.color)
                }
            }
            figure(row, tint: tint)
            // No percentage (estimate from the logs): a meter with no fill would only be a bare track.
            if row.fill(display) != nil {
                AgentsMeter(fill: row.fill(display), marker: row.paceMarker(display), tint: tint, barHeight: 8)
            }
            if let renewal = row.renewal {
                AgentsNote(renewalText(renewal))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .opacity(limits.isStale ? 0.7 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.title)
        .accessibilityValue([row.valueText(display), row.level?.label, row.renewal.map(renewalText)]
            .compactMap { $0 }.joined(separator: ", "))
    }

    @ViewBuilder private func figure(_ row: LimitRow, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: IslandSpacing.xs) {
            if let fill = row.fill(display) {
                Text(UsageFormat.percent(fill))
                    .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(tint)
                Text(AgentsStrings.text(display == .used ? "used" : "remaining").lowercased())
                    .font(.islandBody).foregroundStyle(IslandPalette.textSecondary.color)
            } else if let tokens = row.tokens {
                Text(UsageFormat.tokens(tokens))
                    .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(tint)
                Text(AgentsStrings.tokensUnknown)
                    .font(.islandBody).foregroundStyle(IslandPalette.textSecondary.color)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func renewalText(_ renewal: Date) -> String {
        let clock = "\(AgentsStrings.renewsAt) \(UsageFormat.clock(renewal))"
        let remaining = renewal.timeIntervalSince(now)
        guard remaining > 0 else { return clock }
        return "\(clock) · \(AgentsStrings.fill(constant: AgentsStrings.inFormat, UsageFormat.duration(remaining)))"
    }

    // MARK: header and footer

    @ViewBuilder private var updated: some View {
        if limits.source == .planFile, let date = limits.updated {
            if limits.isStale {
                Label(AgentsStrings.format("updatedFormat", UsageFormat.relative(date, now: now)),
                      systemImage: IslandStatus.warning.symbol)
                    .font(.islandFootnote).foregroundStyle(IslandStatus.warning.color)
            } else {
                Text(AgentsStrings.format("updatedFormat", UsageFormat.relative(date, now: now)))
                    .font(.islandFootnote).foregroundStyle(IslandPalette.textTertiary.color)
            }
        }
    }

    private var footerNotes: [String] {
        var notes: [String] = []
        switch limits.source {
        case .estimatedFromLogs:
            notes.append(AgentsStrings.text("estimated"))
        case .planFile:
            if limits.hasEstimatedRow { notes.append(AgentsStrings.sessionEstimatedNote) }
            if let extra = limits.extraUsage, extra > 0 {
                notes.append(AgentsStrings.fill(constant: AgentsStrings.extraUsageFormat, UsageFormat.percent(Double(extra) / 100)))
            }
        case .none:
            break
        }
        if limits.rows.contains(where: { $0.fill(display) != nil && $0.paceMarker(display) != nil }) { notes.append(AgentsStrings.paceLegend) }
        return notes
    }

    @ViewBuilder private var footer: some View {
        let notes = footerNotes
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: IslandSpacing.xxs) {
                ForEach(notes, id: \.self) { AgentsNote($0) }
            }
        }
    }

    /// Color follows what is left, whichever way the figure is shown.
    static func tint(_ row: LimitRow) -> Color {
        row.level?.status.color ?? IslandPalette.accent.color
    }
}
