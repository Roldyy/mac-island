import IslandUI
import SwiftUI

/// A moving highlight over a placeholder shape. Static under Reduce Motion.
private struct AgentsShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -0.6

    func body(content: Content) -> some View {
        content.overlay {
            if !reduceMotion {
                GeometryReader { proxy in
                    LinearGradient(colors: [.clear, IslandPalette.textPrimary.color.opacity(0.16), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: proxy.size.width * 0.6)
                        .offset(x: proxy.size.width * phase)
                }
                .mask(content)
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1.0 }
        }
    }
}

extension View {
    /// Marks a placeholder: a faint fill with a sweeping shimmer.
    func agentsShimmer() -> some View { modifier(AgentsShimmer()) }
}

/// A placeholder for a number or a line that is not known yet.
struct AgentsSkeletonBar: View {
    var width: CGFloat?
    var height: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: min(height / 2, IslandRadius.small), style: .continuous)
            .fill(IslandPalette.textPrimary.color.opacity(0.10))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .agentsShimmer()
            .accessibilityHidden(true)
    }
}

/// A placeholder card with the real header: the page keeps its shape while its numbers load.
struct AgentsSkeletonCard: View {
    let card: AgentsCard

    var body: some View {
        AgentsCardFrame(card) {
            VStack(alignment: .leading, spacing: IslandSpacing.s) {
                if card == .models || card == .projects {
                    ForEach(0..<4, id: \.self) { _ in AgentsSkeletonBar(height: 14) }
                } else {
                    AgentsSkeletonBar(width: 120, height: 26)
                    AgentsSkeletonBar(height: 10)
                    AgentsSkeletonBar(width: 160, height: 10)
                    if card == .trend || card == .activity { AgentsSkeletonBar(height: 56) }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.title)
        .accessibilityValue(AgentsStrings.text("loading"))
    }
}
