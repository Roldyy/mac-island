import Combine
import PortKit

/// What the island shell needs from whoever runs the keep-awake sessions. The one implementation is the ported
/// `KeepAwakeManager` (timers, end time, automation, mouse jiggle, display sleep, closed lid); tests plug a fake.
@MainActor
protocol KeepAwakeBackend: AnyObject {
    var snapshot: PortKeepAwake.Snapshot { get }
    /// The current state first, then one value per change.
    func snapshots() -> AnyPublisher<PortKeepAwake.Snapshot, Never>
    /// The saved default duration in minutes; 0 = no limit.
    var defaultMinutes: Int { get }
    /// Stops a running session, otherwise starts the last pick.
    func toggle()
    /// Starts (or restarts) a session of `minutes`; 0 = no limit.
    func start(minutes: Int)
    func stop()
}

/// The real thing: PortKit's facade over the ported manager.
@MainActor
final class PortKeepAwakeBackend: KeepAwakeBackend {
    var snapshot: PortKeepAwake.Snapshot { PortKeepAwake.snapshot }
    func snapshots() -> AnyPublisher<PortKeepAwake.Snapshot, Never> { PortKeepAwake.snapshots() }
    var defaultMinutes: Int { PortKeepAwake.defaultMinutes }
    func toggle() { PortKeepAwake.toggle() }
    func start(minutes: Int) { PortKeepAwake.start(minutes: minutes) }
    func stop() { PortKeepAwake.stop() }
}
