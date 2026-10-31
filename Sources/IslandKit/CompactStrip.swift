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
        let wing = NotchGeometry.baseWing + NotchGeometry.wingExtent(for: layout)
        HStack(spacing: 0) {
            wingView(layout.leading).frame(width: wing)
            Color.clear.frame(width: notchWidth)
            wingView(layout.trailing).frame(width: wing)
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
                glyph(item)
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
