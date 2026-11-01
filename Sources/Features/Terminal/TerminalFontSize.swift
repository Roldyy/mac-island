import Foundation

/// Terminal font size: clamped, stepped by the zoom shortcuts, remembered between launches.
struct TerminalFontSize {
    static let key = "terminalFontSize"
    static let range: ClosedRange<Double> = 9...32
    static let defaultSize = 12.5

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    static func clamp(_ size: Double) -> Double {
        guard size.isFinite else { return defaultSize }
        return min(range.upperBound, max(range.lowerBound, size))
    }

    /// The size after a zoom action; other actions leave it unchanged.
    static func next(_ size: Double, action: TerminalKeyAction) -> Double {
        switch action {
        case .fontLarger: return clamp(size + 1)
        case .fontSmaller: return clamp(size - 1)
        case .fontReset: return defaultSize
        default: return clamp(size)
        }
    }

    var current: Double {
        get { Self.clamp((defaults.object(forKey: Self.key) as? NSNumber)?.doubleValue ?? Self.defaultSize) }
        nonmutating set { defaults.set(Self.clamp(newValue), forKey: Self.key) }
    }
}
