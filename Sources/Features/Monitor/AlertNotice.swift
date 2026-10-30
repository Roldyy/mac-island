import Foundation

/// The in-island notice the shell shows in the wings while an alert is active.
public struct AlertNotice: Equatable, Sendable, Identifiable {
    public let metric: AlertMetric
    public let value: Double
    public let raisedAt: Date

    public var id: AlertMetric { metric }

    public var title: String {
        switch metric {
        case .cpu: "Processeur très sollicité"
        case .memory: "Mémoire presque saturée"
        }
    }

    public var message: String { "Utilisation à \(Int(value.rounded())) %" }
}
