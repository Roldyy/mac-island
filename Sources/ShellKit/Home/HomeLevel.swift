import Foundation
import Observation

/// One Home slider: its value, whether the system lets us act on it, and why not.
@MainActor @Observable
public final class HomeLevel {
    public let title: String
    public let systemImage: String
    public private(set) var value: Double = 0
    public private(set) var isAvailable = false

    @ObservationIgnored private let backend: LevelBackend

    public init(title: String, systemImage: String, backend: LevelBackend) {
        self.title = title
        self.systemImage = systemImage
        self.backend = backend
        refresh()
    }

    public var unavailableReason: String { backend.unavailableReason }

    /// Re-reads the system. The slider calls it while the island is open, so a volume key shows up.
    public func refresh() {
        apply(backend.read())
    }

    /// Assigns only what changed: `@Observable` publishes on every assignment, even of an equal value, and the
    /// poll runs every second while the island is open.
    private func apply(_ level: Double?) {
        if let level {
            let next = Self.clamped(level)
            if value != next { value = next }
            if !isAvailable { isAvailable = true }
        } else if isAvailable {
            isAvailable = false
        }
    }

    /// Applies a level chosen by the user. The shown value follows the system when the write is refused.
    public func set(_ level: Double) {
        let clamped = Self.clamped(level)
        guard isAvailable else { return }
        if value != clamped { value = clamped }
        if !backend.write(clamped) { refresh() }
    }

    nonisolated static func clamped(_ value: Double) -> Double {
        value.isNaN ? 0 : min(max(value, 0), 1)
    }
}
