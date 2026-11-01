import Foundation
import Testing
@testable import PortKit

/// Crash recovery must run BEFORE the registry starts any ported feature. A feature that starts first (the mouse
/// acceleration, the gamma dim) writes its own journal, and a recovery that ran afterwards would read that fresh
/// journal as a crash and undo the feature on every launch.
@MainActor
@Suite struct LaunchRecoveryOrderTests {
    @Test func theRecoveryRunsBeforeTheStartersAndOnlyThen() {
        var events: [String] = []
        PortBridge.launchAfterRecovery(recover: { events.append("recover") },
                                       start: { events.append("starter:mouseAcceleration") })
        #expect(events == ["recover", "starter:mouseAcceleration"])
    }

    @Test func theRealRecoveryHasAlreadyRunWhenTheFirstStarterExecutes() {
        PortHostFixture.isolated { _ in
            PortBridge.resetRecoveryForTesting()
            var recoveredWhenStarted: Bool?
            var runsWhenStarted: Int?
            PortBridge.launchAfterRecovery {
                recoveredWhenStarted = PortBridge.hasRecoveredAtLaunch
                runsWhenStarted = PortBridge.recoveryRuns
            }
            #expect(recoveredWhenStarted == true, "a starter that ran first would have written a journal recovery then undoes")
            #expect(runsWhenStarted == 1)
        }
    }

    @Test func theLaterInstallCallFindsTheRecoveryDone() {
        PortHostFixture.isolated { defaults in
            PortBridge.resetRecoveryForTesting()
            PortBridge.launchAfterRecovery {}
            #expect(PortBridge.recoveryRuns == 1)
            PortBridge.recoverAtLaunch(defaults: defaults)  // what `PortBridge.install` calls
            PortBridge.recoverAtLaunch(defaults: defaults)
            #expect(PortBridge.recoveryRuns == 1, "idempotent: the second call is a no-op")
        }
    }

    @Test func theAppDelegateStartsTheRegistryOnlyThroughTheRecoveryDoor() throws {
        let source = try String(
            contentsOf: PortSourceScrubTests.repoRoot.appendingPathComponent("Sources/MacIsland/AppDelegate.swift"),
            encoding: .utf8)
        let door = try #require(source.range(of: "PortBridge.launchAfterRecovery {"))
        let launch = try #require(source.range(of: "registry.launch("))
        #expect(door.lowerBound < launch.lowerBound, "registry.launch sits inside the closure of the recovery door")
        #expect(source.components(separatedBy: "registry.launch(").count == 2, "no second, unguarded launch")
    }
}
