import IslandUI
import SwiftUI

private struct AgentsSettledKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// True in snapshots, where no display link runs: entry animations (gauge sweep, sparkline reveal) start at
    /// their end value instead of waiting for frames that never come.
    var agentsSettled: Bool {
        get { self[AgentsSettledKey.self] }
        set { self[AgentsSettledKey.self] = newValue }
    }
}

/// A ring gauge: the fill sweeps in from zero when it appears and eases to every new value. A white tick
/// marks the even pace over the window. `fill` nil (unknown) draws the bare track only.
struct AgentsGauge<Center: View>: View {
    let fill: Double?
    let tint: Color
    var pace: Double?
    var lineWidth: CGFloat = 10
    let center: Center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.agentsSettled) private var settled
    @State private var shown = 0.0

    init(fill: Double?, tint: Color, pace: Double? = nil, lineWidth: CGFloat = 10, @ViewBuilder center: () -> Center) {
        self.fill = fill
        self.tint = tint
        self.pace = pace
        self.lineWidth = lineWidth
        self.center = center()
    }

    var body: some View {
        GeometryReader { proxy in
            let radius = min(proxy.size.width, proxy.size.height) / 2 - lineWidth / 2
            ZStack {
                // Dashed when there is no measurement (log estimate): the ring then only tells the time.
                Circle().stroke(IslandPalette.textPrimary.color.opacity(fill == nil ? 0.20 : 0.12),
                                style: StrokeStyle(lineWidth: lineWidth, dash: fill == nil ? [3, 5] : []))
                if fill != nil, shown > 0.004 {
                    Circle()
                        .trim(from: 0, to: min(1, shown))
                        .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: tint.opacity(0.35), radius: lineWidth / 2)
                }
                if let pace {
                    Capsule()
                        .fill(IslandPalette.textPrimary.color)
                        .frame(width: 2.5, height: lineWidth + 6)
                        .shadow(color: .black.opacity(0.6), radius: 1)
                        .offset(y: -radius)
                        .rotationEffect(.degrees(min(1, max(0, pace)) * 360))
                }
                center
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onAppear { sweep() }
        .onChange(of: fill) { sweep() }
        .accessibilityHidden(true)
    }

    private func sweep() {
        guard !settled else {
            shown = fill ?? 0
            return
        }
        withAnimation(IslandMotion.animation(.easeOut(duration: 0.9), reduceMotion: reduceMotion)) {
            shown = fill ?? 0
        }
    }
}
