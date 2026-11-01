import Foundation

/// The keyboard backlight as the Home slider sees it. The app binds the real device (CoreBrightness, behind the
/// ported capability probe); tests bind a fake. ShellKit never touches the private API itself.
@MainActor
public protocol KeyboardBacklighting: AnyObject {
    /// The level, 0...1. Nil when this Mac has no controllable keyboard backlight (probe failed): the slider is
    /// then hidden. Reading never changes the backlight.
    func currentLevel() -> Double?
    /// Sets the level (already clamped to 0...1 by the caller). False when the system refused.
    func setLevel(_ level: Double) -> Bool
}

extension LevelBackend {
    /// The Home slider backend of a keyboard backlight. Nil device, or a device that cannot be read, reads as
    /// unavailable so the Home leaves the slider out.
    public static func keyboardBacklight(_ device: (any KeyboardBacklighting)?) -> LevelBackend {
        let reason = "Pas de rétroéclairage de clavier réglable sur ce Mac"
        guard let device else { return .unsupported(reason) }
        // `HomeLevel` is main-actor and is the only caller of these closures.
        return LevelBackend(
            read: { MainActor.assumeIsolated { device.currentLevel() } },
            write: { level in MainActor.assumeIsolated { device.setLevel(level) } },
            unavailableReason: reason)
    }
}
