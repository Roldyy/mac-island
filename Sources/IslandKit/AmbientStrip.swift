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
    /// Width of each wing beyond the notch. Nil: both are half of what `size` leaves beside the notch.
    public let leadingWing: CGFloat?
    public let trailingWing: CGFloat?
    /// Tests freeze the clock and the pulse here.
    public var clock: Date?
    public var pulsePreview: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(content: ClosedIslandContent, notchWidth: CGFloat, isNotched: Bool, size: CGSize,
                leadingWing: CGFloat? = nil, trailingWing: CGFloat? = nil,
                clock: Date? = nil, pulsePreview: Double? = nil) {
        self.content = content
        self.notchWidth = notchWidth
        self.isNotched = isNotched
        self.size = size
        self.leadingWing = leadingWing
        self.trailingWing = trailingWing
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
                    .padding(.top, 2).padding(.trailing, 3)
                    .accessibilityLabel(CompactStrip.dotLabel(dot))
            }
        }
        .animation(reduceMotion ? nil : AmbientMotion.morph, value: content)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Layouts

    private var wings: some View {
        let even = max(0, (size.width - notchWidth) / 2)
        let leadingWidth = max(0, leadingWing ?? even), trailingWidth = max(0, trailingWing ?? even)
        // Each group sits against the notch (the clock right beside it), the free end of the wing outside.
        return HStack(spacing: 0) {
            group(content.leading)
                .padding(.trailing, AmbientMetrics.wingPadding)
                .frame(width: leadingWidth, alignment: .trailing)
            Color.clear.frame(width: notchWidth)
            group(content.trailing)
                .padding(.leading, AmbientMetrics.wingPadding)
                .frame(width: trailingWidth, alignment: .leading)
        }
    }

    @ViewBuilder
    private var pill: some View {
        if let center = content.center { centeredPill(center) } else { plainPill }
    }

    /// Three zones. Both sides get the same width, so the clock sits exactly in the middle of the pill even when
    /// only one side has something to show; the groups hug the clock.
    private func centeredPill(_ center: AmbientIndicator) -> some View {
        let middle = AmbientMetrics.centerWidth(center)
        let side = max(0, (size.width - middle) / 2)
        return HStack(spacing: 0) {
            group(content.leading)
                .padding(.trailing, AmbientMetrics.centerGap)
                .frame(width: side, alignment: .trailing)
            AmbientCenterClock(item: center)
                .frame(width: middle)
            group(content.trailing)
                .padding(.leading, AmbientMetrics.centerGap)
                .frame(width: side, alignment: .leading)
        }
    }

    private var plainPill: some View {
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
