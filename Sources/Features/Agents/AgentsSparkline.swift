import IslandUI
import SwiftUI

/// The outline of a series: the line itself, or the same line closed down to the baseline (for the fill).
private struct SparklineShape: Shape {
    let values: [Double]
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        let points = AgentsSparkline.points(values, in: rect.size)
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        if closed {
            path.addLine(to: CGPoint(x: last.x, y: rect.height))
            path.addLine(to: CGPoint(x: first.x, y: rect.height))
            path.closeSubpath()
        }
        return path
    }
}

/// A tiny area line over a series (one point per hour). A flat dotted baseline when everything is zero.
struct AgentsSparkline: View {
    let values: [Double]
    var tint: Color = IslandStatus.success.color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.agentsSettled) private var settled
    @State private var reveal = 0.0

    /// Points of the line inside a box, left to right, the peak touching the top. Pure.
    static func points(_ values: [Double], in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return values.isEmpty ? [] : [CGPoint(x: 0, y: size.height - 1.5)] }
        let peak = max(values.max() ?? 0, 0.000_001)
        return values.enumerated().map { index, value in
            CGPoint(x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                    y: size.height - (size.height - 4) * CGFloat(value / peak) - 2)
        }
    }

    private var hasData: Bool { (values.max() ?? 0) > 0 }

    var body: some View {
        GeometryReader { proxy in
            if hasData {
                ZStack {
                    SparklineShape(values: values, closed: true)
                        .fill(LinearGradient(colors: [tint.opacity(0.32), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                    SparklineShape(values: values, closed: false)
                        .stroke(tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    if let last = Self.points(values, in: proxy.size).last {
                        Circle().fill(tint).frame(width: 6, height: 6).position(last)
                    }
                }
                .mask(alignment: .leading) { Rectangle().frame(width: proxy.size.width * reveal + 4) }
            } else {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: proxy.size.height - 2))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height - 2))
                }
                .stroke(IslandPalette.textPrimary.color.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 4]))
            }
        }
        .onAppear {
            if reduceMotion || settled {
                reveal = 1
            } else {
                withAnimation(.easeOut(duration: 0.8)) { reveal = 1 }
            }
        }
        .accessibilityHidden(true)
    }
}
