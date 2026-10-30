import FanShared
import SwiftUI

/// Current speed, limits and mode of every fan, read directly from the SMC (no helper needed).
struct MonitoringSection: View {
    let model: FansModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ventilateurs")
                .font(.headline)
                .foregroundStyle(.white)
            if let error = model.readError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if model.readings.isEmpty {
                Text("Lecture en cours…")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            ForEach(model.readings) { reading in
                FanRowView(reading: reading)
            }
        }
    }
}

struct FanRowView: View {
    let reading: FanReading

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "fan")
                    .foregroundStyle(.white.opacity(0.7))
                    .accessibilityHidden(true)
                Text("Ventilateur \(reading.index + 1)")
                    .foregroundStyle(.white)
                Spacer()
                Text(FanFormat.rpm(reading.actualRPM))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            Text("min \(FanFormat.rpm(reading.minRPM)) · max \(FanFormat.rpm(reading.maxRPM)) · \(FanFormat.mode(reading.mode))")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ventilateur \(reading.index + 1)")
        .accessibilityValue("""
            \(FanFormat.spoken(reading.actualRPM)), minimum \(FanFormat.spoken(reading.minRPM)), \
            maximum \(FanFormat.spoken(reading.maxRPM)), mode \(FanFormat.mode(reading.mode))
            """)
    }
}

enum FanFormat {
    static func rpm(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(value.formatted(.number.precision(.fractionLength(0)))) tr/min"
    }

    static func spoken(_ value: Double?) -> String {
        guard let value else { return "inconnu" }
        return "\(value.formatted(.number.precision(.fractionLength(0)))) tours par minute"
    }

    static func mode(_ mode: FanMode) -> String {
        switch mode {
        case .automatic: "automatique"
        case .manual: "manuel"
        case .unknown: "inconnu"
        }
    }
}
