import AppKit
import Foundation
import IslandKit

/// Tells whether a reading differs from the previous one. The first reading always counts, so the sampler posts or
/// withdraws once at start and then only on a real flip. Pure.
struct CapsLockEdgeDetector: Equatable, Sendable {
    private var last: Bool?

    mutating func changed(to on: Bool) -> Bool {
        defer { last = on }
        return last != on
    }
}

/// "Verr. Maj" in the closed island, only while Caps Lock is on. A quarter-second poll of
/// `NSEvent.modifierFlags` (public API, no permission, no event tap): the read hops to the main actor, where AppKit
/// documents nothing about other threads, and a 4 Hz read of one flag costs next to nothing. The hub runs it only
/// while the channel is on and the closed strip is on screen, so an open island or a disabled indicator polls nothing.
@MainActor
public final class CapsLockSampler: AmbientSampler {
    public let channel = AmbientChannel.capsLock
    public nonisolated static let interval: Duration = .milliseconds(250)

    private weak var center: AmbientCenter?
    private let read: @MainActor () -> Bool
    private var detector = CapsLockEdgeDetector()
    private var poller: AmbientPoller?
    private let interval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void

    public convenience init(center: AmbientCenter) {
        self.init(center: center, read: { NSEvent.modifierFlags.contains(.capsLock) })
    }

    init(center: AmbientCenter, interval: Duration = CapsLockSampler.interval,
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         read: @escaping @MainActor () -> Bool) {
        self.center = center
        self.interval = interval
        self.sleep = sleep
        self.read = read
    }

    public var isRunning: Bool { poller?.isRunning ?? false }

    /// One reading: posts while on, withdraws while off, and does nothing when nothing flipped.
    func poll() {
        let on = read()
        guard detector.changed(to: on) else { return }
        if on { center?.post(AmbientReadings.capsLock()) } else { center?.withdraw(id: AmbientReadings.capsLockID) }
    }

    public func start(settings: ClosedIslandSettings) {
        guard poller == nil else { return }
        let poller = AmbientPoller(interval: interval, sleep: sleep) { [weak self] in
            Task { @MainActor in self?.poll() }
        }
        self.poller = poller
        poller.start()
    }

    public func stop() {
        poller?.stop()
        poller = nil
        detector = CapsLockEdgeDetector()
        center?.withdraw(id: AmbientReadings.capsLockID)
    }
}
