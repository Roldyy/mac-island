import SwiftUI

/// Dot + label for the island wings: Travaille (orange), Attend (blue), Termine (green). Hidden when idle.
public struct ClaudeStatusPill: View {
    @ObservedObject private var model: ClaudeStatusModel

    public init(model: ClaudeStatusModel) {
        self.model = model
    }

    public var body: some View {
        if let style = Style(model.status) {
            HStack(spacing: 5) {
                Circle().fill(style.color).frame(width: 7, height: 7)
                Text(style.label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(style.accessibility)
        }
    }

    struct Style: Equatable {
        let label: String
        let accessibility: String
        let color: Color

        init?(_ status: ClaudeStatus) {
            switch status {
            case .idle: return nil
            case .working:
                self.init(label: "Travaille", accessibility: "Claude travaille", color: .orange)
            case .waiting:
                self.init(label: "Attend", accessibility: "Claude attend votre réponse", color: .blue)
            case .done:
                self.init(label: "Terminé", accessibility: "Claude a terminé", color: .green)
            }
        }

        private init(label: String, accessibility: String, color: Color) {
            self.label = label
            self.accessibility = accessibility
            self.color = color
        }
    }
}
