import Foundation
import IslandKit

/// Thresholds and French text of the built-in chips, with no system call: numbers in, level and words out.
public enum StatusChipLevels {
    public typealias Level = StatusChipReading.Level

    /// Processor load, 0...1. Judged on the value the chip shows (rounded to 5 %), like the closed island's pill:
    /// attention from 75 %, alert from 90 %.
    public static func cpu(_ fraction: Double) -> Level {
        let shown = AmbientFormat.roundedPercent(fraction)
        return shown >= 90 ? .alert : shown >= 75 ? .attention : .normal
    }

    /// The kernel's own verdict on memory: elevated is attention, critical is alert.
    public static func memory(_ pressure: MemoryPressure) -> Level {
        switch pressure {
        case .normal: .normal
        case .warning: .attention
        case .critical: .alert
        }
    }

    /// Free space as a fraction of the volume, 0...1: attention under 10 %, alert under 5 %.
    public static func disk(freeFraction: Double) -> Level {
        guard freeFraction.isFinite else { return .normal }
        return freeFraction < 0.05 ? .alert : freeFraction < 0.10 ? .attention : .normal
    }

    // MARK: - Text

    /// "23 %": French spacing, rounded to `step` (5 for the processor, 1 for the memory).
    public static func percent(_ fraction: Double, step: Int = 5) -> String {
        "\(AmbientFormat.roundedPercent(fraction, step: step)) %"
    }

    /// "62 °C".
    public static func temperature(_ celsius: Double) -> String {
        celsius.isFinite ? "\(Int(celsius.rounded())) °C" : "—"
    }

    /// "↓ 1,2 Mo/s  ↑ 80 Ko/s".
    public static func rates(down: Double, up: Double) -> String {
        "↓ \(AmbientFormat.rate(down))  ↑ \(AmbientFormat.rate(up))"
    }
}
