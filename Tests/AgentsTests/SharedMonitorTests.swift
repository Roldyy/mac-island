import ClaudeLiveKit
import Foundation
import Testing
@testable import AgentsFeature

@Suite @MainActor struct SharedMonitorTests {
    @Test func theTabReadsTheAppsOneSharedMonitor() {
        #expect(AgentsLiveModel().monitor === ClaudeLiveMonitor.shared)
    }

    @Test func theTabHoldsTheMonitorOnlyWhileItIsOnScreen() {
        let monitor = ClaudeLiveMonitor(snapshot: { [] })
        let live = AgentsLiveModel(monitor: monitor)
        live.start()
        live.start()   // a second appear does not count twice
        #expect(monitor.isRunning)
        live.stop()
        #expect(!monitor.isRunning)
    }
}
