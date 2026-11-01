import PortKit
import ShellKit

/// Binds the island Home slider to the ported keyboard backlight (CoreBrightness, behind its capability probe).
@MainActor
final class PortKeyboardBacklight: KeyboardBacklighting {
    func currentLevel() -> Double? { PortKeyboardLight.level() }
    func setLevel(_ level: Double) -> Bool { PortKeyboardLight.setLevel(level) }
}
