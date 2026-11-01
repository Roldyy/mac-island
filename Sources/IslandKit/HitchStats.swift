import Foundation

/// Plain numbers over a list of run-loop iteration times (milliseconds). Pure, so the hitch budgets and the
/// probe's own tests do not need a run loop.
public struct HitchStats: Equatable, Sendable {
    public var iterations: Int
    /// The limit, in milliseconds, that `overThreshold` counts against.
    public var threshold: Double
    /// Iterations strictly longer than `threshold`.
    public var overThreshold: Int
    public var median: Double
    public var p95: Double
    public var worst: Double

    public static let empty = HitchStats(iterations: 0, threshold: HitchProbe.defaultThresholdMilliseconds, overThreshold: 0, median: 0, p95: 0, worst: 0)

    public init(iterations: Int, threshold: Double, overThreshold: Int, median: Double, p95: Double, worst: Double) {
        self.iterations = iterations
        self.threshold = threshold
        self.overThreshold = overThreshold
        self.median = median
        self.p95 = p95
        self.worst = worst
    }

    public init(milliseconds: [Double], threshold: Double = HitchProbe.defaultThresholdMilliseconds) {
        let clean = milliseconds.filter { $0.isFinite && $0 >= 0 }.sorted()
        guard !clean.isEmpty else {
            self = HitchStats(iterations: 0, threshold: threshold, overThreshold: 0, median: 0, p95: 0, worst: 0)
            return
        }
        self.init(iterations: clean.count, threshold: threshold, overThreshold: clean.filter { $0 > threshold }.count,
                  median: Self.percentile(sorted: clean, 0.5), p95: Self.percentile(sorted: clean, 0.95),
                  worst: clean[clean.count - 1])
    }

    /// Nearest-rank percentile of an ascending list; `p` is clamped to 0...1.
    public static func percentile(sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let rank = Int((min(max(p, 0), 1) * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank - 1, 0), sorted.count - 1)]
    }

    /// One line, counts and durations only: `n=412 over8=3 p50=0.4 p95=2.1 max=19.6`.
    public var line: String {
        String(format: "n=%d over%g=%d p50=%.1f p95=%.1f max=%.1f", iterations, threshold, overThreshold, median, p95, worst)
    }
}
