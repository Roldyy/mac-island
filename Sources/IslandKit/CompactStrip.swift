import Foundation
import SwiftUI
import IslandUI

/// The closed island's wings and edge dot. The hosting panel is already as wide as
/// `NotchGeometry.closedFrame` says, so this view only has to leave the notch gap empty.
public struct CompactStrip: View {
    public let layout: ActivityLayout
    /// Width of the hardware notch (or the pill) the two wings must stay clear of.
    public let notchWidth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(layout: ActivityLayout, notchWidth: CGFloat = NotchGeometry.pillWidth) {
        self.layout = layout
        self.notchWidth = notchWidth
    }

    public var body: some View {
        let wings = NotchGeometry.wingWidths(for: layout)
        HStack(spacing: 0) {
            wingView(layout.leading).frame(width: wings.leading)
            Color.clear.frame(width: notchWidth)
            wingView(layout.trailing).frame(width: wings.trailing)
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if let dot = layout.dot {
                Image(systemName: dot.symbol)
                    .font(.system(size: IslandType.minimumSize, weight: .bold))
                    .foregroundStyle(dot.color)
                    .padding(.top, 3).padding(.trailing, 3)
                    .accessibilityLabel(Self.dotLabel(dot))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: layout)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func wingView(_ item: CompactItem?) -> some View {
        if let item {
            HStack(spacing: 4) {
                if !item.symbol.isEmpty { glyph(item) }
                if let text = item.text, !text.isEmpty {
                    Text(text)
                        .font(.system(size: IslandType.minimumSize, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.accessibilityLabel(for: item))
        } else {
            Color.clear
        }
    }

    private func glyph(_ item: CompactItem) -> some View {
        ZStack {
            if let progress = item.progress {
                Circle().stroke(item.status.color.opacity(0.25), lineWidth: 1.5)
                Circle()
                    .trim(from: 0, to: Self.clampedProgress(progress))
                    .stroke(item.status.color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: item.symbol)
                .font(.system(size: item.progress == nil ? 12 : IslandType.minimumSize, weight: .semibold))
                .foregroundStyle(item.status.color)
        }
        .frame(width: 16, height: 16)
    }

    // MARK: - Pure helpers (tested)

    static func clampedProgress(_ value: Double) -> Double {
        value.isNaN ? 0 : min(max(value, 0), 1)
    }

    /// Color alone never carries the state, so VoiceOver gets the status in words.
    static func statusWord(_ status: IslandStatus) -> String? {
        switch status {
        case .neutral: nil
        case .info: "information"
        case .success: "réussite"
        case .warning: "attention"
        case .danger: "erreur"
        }
    }

    static func accessibilityLabel(for item: CompactItem) -> String {
        var parts: [String] = []
        if let text = item.text, !text.isEmpty { parts.append(text) }
        if let word = statusWord(item.status) { parts.append(word) }
        if let progress = item.progress { parts.append("\(Int((clampedProgress(progress) * 100).rounded())) %") }
        return parts.isEmpty ? "Activité en cours" : parts.joined(separator: ", ")
    }

    static func dotLabel(_ status: IslandStatus) -> String {
        guard let word = statusWord(status) else { return "Pastille d'état" }
        return "Pastille d'état : \(word)"
    }
}

// MARK: - Elapsed time (Claude wing)

/// `m:ss`, or `h:mm:ss` from one hour. Negative and non-finite values read `0:00`.
public enum ElapsedTime {
    public static func text(_ seconds: TimeInterval) -> String {
        let total = seconds.isFinite ? Int(min(max(seconds, 0), 359_999)) : 0
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        let two = { (n: Int) in n < 10 ? "0\(n)" : "\(n)" }
        return hours > 0 ? "\(hours):\(two(minutes)):\(two(secs))" : "\(minutes):\(two(secs))"
    }

    public static func text(since start: Date, now: Date) -> String { text(now.timeIntervalSince(start)) }
}

/// What the closed island needs to know about one Claude session to show its elapsed time.
public struct ClaudeWorkSample: Equatable, Sendable {
    public let id: String
    public let isWaiting: Bool
    /// When the session entered its current state (`ClaudeSession.updatedAt`).
    public let since: Date?

    public init(id: String, isWaiting: Bool, since: Date?) {
        self.id = id
        self.isWaiting = isWaiting
        self.since = since
    }
}

/// Turns the wing that shows a working or waiting Claude session into "glyph | elapsed time".
/// Pure: the caller feeds the date, so a one-second timeline can redraw it.
public enum ClaudeWing {
    static let workingSymbol = "sparkles"
    static let waitingSymbol = "hand.raised.fill"
    /// The Claude glyph at rest (a solid star reads at 9 pt inside the ring).
    public static let restGlyph = "sparkle"

    /// The Claude mapper's glyph has no text; other `sparkles` users (cleaning countdown) do.
    public static func isClaudeWing(_ item: CompactItem?) -> Bool {
        guard let item, item.text == nil else { return false }
        return (item.symbol == workingSymbol && item.status == .info)
            || (item.symbol == waitingSymbol && item.status == .warning)
    }

    /// Same winner as `ActivityArbiter`: waiting before working, then the smallest id.
    public static func pick(_ samples: [ClaudeWorkSample]) -> ClaudeWorkSample? {
        samples.min { a, b in a.isWaiting != b.isWaiting ? a.isWaiting : a.id < b.id }
    }

    public static func layout(_ base: ActivityLayout, sample: ClaudeWorkSample?, now: Date) -> ActivityLayout {
        guard isClaudeWing(base.leading), let leading = base.leading,
              let since = sample?.since else { return base }
        var out = base
        // Glyph on the left, the clock alone on the right (no glyph: the wing is narrow).
        out.trailing = CompactItem(symbol: "", text: ElapsedTime.text(since: since, now: now), status: leading.status)
        return out
    }
}
