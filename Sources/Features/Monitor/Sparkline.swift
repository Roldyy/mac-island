import SwiftUI

/// Plain-shape history line for a 0...100 signal. Decorative: the gauge next to it carries the value.
struct Sparkline: Shape {
    var values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let step = rect.width / CGFloat(SampleHistory.defaultCapacity - 1)
        // Right-aligned: the newest sample sits on the right edge and the line grows leftwards.
        let startX = rect.width - step * CGFloat(values.count - 1)
        for (i, v) in values.enumerated() {
            let x = startX + step * CGFloat(i)
            let y = rect.height * (1 - CGFloat(min(100, max(0, v))) / 100)
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}
