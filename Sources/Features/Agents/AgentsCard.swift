import Foundation

/// The cards of the page, in their default order. Raw values are the ids Vorssaint stores in
/// `notchAgentsCardOrder` / `notchAgentsHiddenCards`.
enum AgentsCard: String, CaseIterable, Identifiable, Sendable {
    case limits, spend, live, trend, models, projects, activity, resets

    var id: String { rawValue }

    var title: String { AgentsStrings.text(rawValue == "live" ? "liveCard" : rawValue + "Card") }

    var symbol: String {
        switch self {
        case .limits: "gauge.with.dots.needle.67percent"
        case .spend: "dollarsign.circle"
        case .live: "waveform"
        case .trend: "chart.bar.xaxis"
        case .models: "cpu"
        case .projects: "folder"
        case .activity: "square.grid.3x3"
        case .resets: "arrow.counterclockwise.circle"
        }
    }

    /// Charts take the full width; the rest share a row two by two.
    var isFullWidth: Bool { self == .trend || self == .activity }
}
