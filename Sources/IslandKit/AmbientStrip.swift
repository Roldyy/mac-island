import IslandUI
import SwiftUI

/// The closed island, drawn: up to two indicators in each wing around a hardware notch, or all of them in one
/// centered row inside the pill when the screen has no notch. The panel is already as wide as
/// `AmbientMetrics` asked for, so this view only places things.
public struct AmbientStrip: View {
    public let content: ClosedIslandContent
    /// Width of the hardware notch (or of the pill) the two wings stay clear of.
    public let notchWidth: CGFloat
    public let isNotched: Bool
    /// Size of the closed island.
    public let size: CGSize
    /// Tests freeze the clock and the pulse here.
    public var clock: Date?
    public var pulsePreview: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(content: ClosedIslandContent, notchWidth: CGFloat, isNotched: Bool, size: CGSize,
                clock: Date? = nil, pulsePreview: Double? = nil) {
        self.content = content
        self.notchWidth = notchWidth
        self.isNotched = isNotched
        self.size = size
        self.clock = clock
        self.pulsePreview = pulsePreview
    }

    public var body: some View {
        ZStack {
            if !isNotched { AmbientPillChrome() }
            if isNotched { wings } else { pill }
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .topTrailing) {
            if let dot = content.dot {
                Image(systemName: dot.symbol)
                    .font(.system(size: IslandType.minimumSize, weight: .bold))
                    .foregroundStyle(dot.color)
                    .padding(.top, 3).padding(.trailing, 4)
                    .accessibilityLabel(CompactStrip.dotLabel(dot))
            }
        }
        .animation(reduceMotion ? nil : AmbientMotion.morph, value: content)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Layouts

    private var wings: some View {
        let wing = max(0, (size.width - notchWidth) / 2)
        return HStack(spacing: 0) {
            group(content.leading).frame(width: wing)
            Color.clear.frame(width: notchWidth)
            group(content.trailing).frame(width: wing)
        }
    }

    private var pill: some View {
        HStack(spacing: 0) {
            group(content.leading)
            if !content.leading.isEmpty, !content.trailing.isEmpty {
                Capsule()
                    .fill(IslandPalette.textTertiary.color.opacity(0.4))
                    .frame(width: 1, height: 10)
                    .padding(.horizontal, AmbientMetrics.groupGap / 2)
                    .transition(.opacity)
            }
            group(content.trailing)
        }
    }

    private func group(_ items: [AmbientIndicator]) -> some View {
        HStack(spacing: AmbientMetrics.elementGap) {
            ForEach(items) { item in
                AmbientElementView(item: item, clock: clock, pulsePreview: pulsePreview)
                    .transition(.ambientSwap(reduceMotion: reduceMotion))
            }
        }
    }
}
