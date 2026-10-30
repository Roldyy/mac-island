import Foundation
import Observation

/// Slider state for the built-in display. Writes are debounced so dragging the slider sends
/// one value, not hundreds. Every system call goes through `BrightnessBackend`.
@MainActor @Observable
final class BrightnessModel {
    enum Direction { case up, down }

    /// Keyboard brightness uses 16 steps; the same grid keeps the buttons familiar.
    static let step: Float = 1.0 / 16.0

    private(set) var level: Float = 0
    private(set) var isAvailable = false
    /// Migrated `brightnessControlEnabled`: when off the tab shows the switch and nothing else.
    var controlEnabled: Bool { didSet { persistEnabled(controlEnabled) } }
    @ObservationIgnored private(set) var pendingWrite: Task<Void, Never>?
    @ObservationIgnored private var initialLevel: Float?
    @ObservationIgnored private let backend: BrightnessBackend
    @ObservationIgnored private let debounce: TimeInterval
    @ObservationIgnored private let sleep: @Sendable (TimeInterval) async -> Void
    @ObservationIgnored private let persistEnabled: (Bool) -> Void

    init(backend: BrightnessBackend, debounce: TimeInterval = 0.05,
         controlEnabled: Bool = true, persistEnabled: @escaping (Bool) -> Void = { _ in },
         sleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
             try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
         }) {
        self.backend = backend
        self.debounce = debounce
        self.sleep = sleep
        self.controlEnabled = controlEnabled
        self.persistEnabled = persistEnabled
    }

    /// Re-read the system level (the user may have used the keyboard keys).
    func refresh() {
        guard let value = backend.read() else {
            isAvailable = false
            return
        }
        isAvailable = true
        level = value
        if initialLevel == nil { initialLevel = value }
    }

    func setLevel(_ value: Float) {
        guard isAvailable, value.isFinite else { return }
        let clamped = min(1, max(0, value))
        level = clamped
        pendingWrite?.cancel()
        pendingWrite = Task { [weak self, sleep, debounce] in
            await sleep(debounce)
            guard !Task.isCancelled, let self else { return }
            self.apply(clamped)
        }
    }

    func nudge(_ direction: Direction) {
        setLevel(level + (direction == .up ? Self.step : -Self.step))
    }

    /// Put back the level seen when the tab first read the display. Written immediately.
    func restoreInitial() {
        guard isAvailable, let initialLevel else { return }
        pendingWrite?.cancel()
        pendingWrite = nil
        level = initialLevel
        apply(initialLevel)
    }

    private func apply(_ value: Float) {
        if !backend.write(value) { isAvailable = false }
    }
}
