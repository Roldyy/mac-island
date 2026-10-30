import Foundation

/// The seam between the brightness model and the system. Real one: `DisplayServicesBackend`.
protocol BrightnessBackend: AnyObject, Sendable {
    /// Current level in 0...1, or nil when the display cannot be read (feature unavailable).
    func read() -> Float?
    /// True when the level was applied.
    func write(_ value: Float) -> Bool
}
