import SwiftUI

// W0 contract stub. Lane L1 owns this whole target and replaces the bodies; the public names below
// are frozen so the other lanes compile against them from day one.

/// Status colors always travel with a symbol, so color is never the only signal.
public enum IslandStatus: String, CaseIterable, Sendable {
    case neutral, info, success, warning, danger

    public var symbol: String {
        switch self {
        case .neutral: "circle"
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .danger: "xmark.octagon.fill"
        }
    }

    public var color: Color {
        switch self {
        case .neutral: .secondary
        case .info: .cyan
        case .success: .green
        case .warning: .orange
        case .danger: .red
        }
    }
}

public extension View {
    /// Frosted-glass surface. L1: system materials, solid fallback for Reduce Transparency.
    func islandGlass(cornerRadius: CGFloat = 14) -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// The single button style of the app. L1 adds `prominent` and `destructive` variants.
public struct IslandButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.quaternary.opacity(configuration.isPressed ? 1 : 0.6), in: Capsule())
    }
}

/// The single switch style of the app.
public struct IslandToggleStyle: ToggleStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack { configuration.label; Spacer(); Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle") }
        }
        .buttonStyle(.plain)
    }
}

/// The single section header.
public struct IslandHeader: View {
    let title: String
    public init(_ title: String) { self.title = title }
    public var body: some View {
        Text(title).font(.system(size: 13, weight: .semibold))
    }
}
