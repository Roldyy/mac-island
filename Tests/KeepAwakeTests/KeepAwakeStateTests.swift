import Combine
import Foundation
import Observation
import PortKit
import Testing
@testable import KeepAwakeFeature

@MainActor
final class FakeBackend: KeepAwakeBackend {
    let subject = CurrentValueSubject<PortKeepAwake.Snapshot, Never>(PortKeepAwake.Snapshot())
    var calls: [String] = []
    var defaultMinutes = 0
    var snapshot: PortKeepAwake.Snapshot { subject.value }
    func snapshots() -> AnyPublisher<PortKeepAwake.Snapshot, Never> { subject.eraseToAnyPublisher() }
    func toggle() { calls.append("toggle") }
    func start(minutes: Int) { calls.append("start \(minutes)") }
    func stop() { calls.append("stop") }
}

/// The shell side of Keep Awake: the Home tile, the shortcut and the closed island's cup all go through
/// `KeepAwakeFeature`, now backed by the ported manager. A fake backend stands in for it.
@Suite(.serialized) @MainActor struct KeepAwakeStateTests {
    @Test func theFacadeForwardsToggleToTheOneImplementation() {
        let backend = FakeBackend()
        KeepAwakeFeature.configure(backend: backend)
        KeepAwakeFeature.toggle()
        KeepAwakeFeature.toggle()
        #expect(backend.calls == ["toggle", "toggle"])
    }

    @Test func isActiveFollowsTheBackend() {
        let backend = FakeBackend()
        KeepAwakeFeature.configure(backend: backend)
        #expect(!KeepAwakeFeature.isActive)
        backend.subject.send(PortKeepAwake.Snapshot(isActive: true))
        #expect(KeepAwakeFeature.isActive)
        backend.subject.send(PortKeepAwake.Snapshot(isActive: true, isAutomatic: true))
        #expect(KeepAwakeFeature.isActive)  // an automatic session counts: the cup shows it too
        backend.subject.send(PortKeepAwake.Snapshot())
        #expect(!KeepAwakeFeature.isActive)
    }

    @Test func theAmbientCupObservationFiresWhenASessionStartsAndStops() {
        // The closed island's cup is `withObservationTracking { KeepAwakeFeature.isActive }` (AppDelegate).
        let backend = FakeBackend()
        KeepAwakeFeature.configure(backend: backend)
        let fired = Box(0)
        let before = withObservationTracking({ KeepAwakeFeature.isActive }, onChange: { fired.value += 1 })
        #expect(!before)
        backend.subject.send(PortKeepAwake.Snapshot(isActive: true, endDate: Date().addingTimeInterval(60)))
        #expect(fired.value == 1)
        let during = withObservationTracking({ KeepAwakeFeature.isActive }, onChange: { fired.value += 1 })
        #expect(during)
        backend.subject.send(PortKeepAwake.Snapshot())
        #expect(fired.value == 2)
    }

    @Test func theIslandHoldGoesThroughTheFacade() {
        let backend = FakeBackend()
        let power = FakePower()
        let hold = IslandActivityHold(power: power, settings: KeepAwakeSettings(defaults: MemoryDefaults()),
                                      runsLoop: false)
        KeepAwakeFeature.configure(backend: backend, hold: hold)
        KeepAwakeFeature.noteIslandActivity()
        #expect(power.live.count == 1)
        #expect(backend.calls.isEmpty, "the hold is not a session")
        hold.release()
    }

    @Test func statusLinePrioritisesTheSafetyStates() {
        typealias S = PortKeepAwake.Snapshot
        #expect(KeepAwakeView.statusLine(for: S()) == nil)
        #expect(KeepAwakeView.statusLine(for: S(isActive: true)) == nil)
        #expect(KeepAwakeView.statusLine(for: S(isActive: true, isAutomatic: true)) == "Démarré automatiquement")
        #expect(KeepAwakeView.statusLine(for: S(isActive: true, closedLidActive: true)) == "Mode capot fermé actif")
        #expect(KeepAwakeView.statusLine(for: S(isActive: true, closedLidActive: true, sleepRestoreNeeded: true))
            == "Veille désactivée : à rétablir dans Réglages")
    }
}
