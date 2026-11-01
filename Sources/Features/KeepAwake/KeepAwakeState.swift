import Combine
import Observation
import PortKit

/// The keep-awake state as an `@Observable`, so the closed island's cup, the Home tile and the Éveil tab follow it
/// with `withObservationTracking` while the sessions themselves live in the ported manager (Combine).
@MainActor @Observable
final class KeepAwakeState {
    private(set) var snapshot: PortKeepAwake.Snapshot
    @ObservationIgnored private var subscription: AnyCancellable?

    init(backend: any KeepAwakeBackend) {
        snapshot = backend.snapshot
        subscription = backend.snapshots().sink { [weak self] value in
            MainActor.assumeIsolated { self?.snapshot = value }
        }
    }

    var isActive: Bool { snapshot.isActive }
}
