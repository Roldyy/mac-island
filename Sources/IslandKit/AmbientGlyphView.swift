import IslandUI
import SwiftUI

/// The glyph of an indicator: a symbol (or the equalizer) with a thin ring around it when there is a
/// percentage, or a turning arc while Claude works. Sized by frame so it never needs a font under 11 pt.
struct AmbientGlyphView: View {
    let item: AmbientIndicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let ringWidth: CGFloat = 2

    private var isRinged: Bool { item.progress != nil || item.isBusy }

    var body: some View {
        ZStack {
            ring
            inner
        }
        .frame(width: AmbientMetrics.glyphSize, height: AmbientMetrics.glyphSize)
    }

    @ViewBuilder
    private var ring: some View {
        let color = item.status.color
        if let progress = item.progress {
            Circle().stroke(color.opacity(0.25), lineWidth: Self.ringWidth)
            Circle()
                .trim(from: 0, to: CompactStrip.clampedProgress(progress))
                .stroke(color, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        } else if item.isBusy {
            Circle().stroke(color.opacity(0.2), lineWidth: Self.ringWidth)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
                let turn = reduceMotion ? 0.12 : timeline.date.timeIntervalSinceReferenceDate / 1.1
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(color, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(turn.truncatingRemainder(dividingBy: 1) * 360 - 90))
            }
        }
    }

    @ViewBuilder
    private var inner: some View {
        switch item.glyph {
        case .none:
            EmptyView()
        case .equalizer:
            AmbientEqualizer(color: item.status.color)
                .scaleEffect(isRinged ? 0.85 : 1)
        case .symbol:
            let side: CGFloat = isRinged ? 9.5 : 14
            if item.symbol.hasPrefix("battery") {
                // The battery keeps a quiet outline and carries the state in its fill.
                Image(systemName: item.symbol)
                    .symbolRenderingMode(.palette)
                    .resizable().scaledToFit()
                    .foregroundStyle(IslandPalette.textSecondary.color, item.status.color)
                    .frame(width: 19, height: 11)
            } else {
                Image(systemName: item.symbol)
                    .symbolRenderingMode(.hierarchical)
                    .resizable().scaledToFit()
                    .foregroundStyle(item.status.color)
                    .frame(width: side, height: side)
            }
        }
    }
}
