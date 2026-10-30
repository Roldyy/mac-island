import SwiftUI

/// A circular gauge with the value in the middle.
struct UsageRing: View {
    let title: String
    let value: Double?
    let threshold: Double
    let history: [Double]

    private var tint: Color {
        guard let value else { return .gray }
        if value >= threshold { return .red }
        if value >= threshold * 0.8 { return .orange }
        return .mint
    }

    private var valueText: String { value.map { "\(Int($0.rounded())) %" } ?? "--" }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: CGFloat((value ?? 0) / 100))
                    .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(valueText)
                    .font(.system(.callout, design: .rounded).monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 64, height: 64)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
            Sparkline(values: history)
                .stroke(tint.opacity(0.9), lineWidth: 1.2)
                .frame(width: 88, height: 22)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value.map { "\(Int($0.rounded())) pour cent" } ?? "indisponible")
    }
}
