import FanShared
import Testing
@testable import FansFeature

/// The Fans model as the ported fan policy's driver: the same client, heartbeat and epoch as the tab, no new path to the
/// helper. Fakes only: no SMC, no XPC, no daemon.
@Suite @MainActor struct FanDriverTests {
    let client = FakeHelperClient()
    let installer = FakeInstaller()
    let heartbeat = FakeHeartbeat()
    let source = FakeReadingSource()

    private func ready() async -> FansModel {
        let model = makeModel(client: client, installer: installer, heartbeat: heartbeat, source: source)
        model.start()
        await model.connectTask?.value
        return model
    }

    @Test func accessAndReachabilityMirrorTheInstallation() async {
        installer.status = .notRegistered
        let model = makeModel(client: client, installer: installer, heartbeat: heartbeat, source: source)
        #expect(model.access == .notRegistered && !model.isReachable)
        installer.status = .requiresApproval
        model.refreshAccess()
        #expect(model.access == .requiresApproval)
        installer.status = .notFound
        model.refreshAccess()
        #expect(model.access == .notFound)
    }

    @Test func readFansComesFromTheReadOnlySourceAndFlagsManualMode() async {
        source.fans = [
            FanReading(index: 0, actualRPM: 4000, minRPM: 2317, maxRPM: 7826, targetRPM: 4000, mode: .manual),
            FanReading(index: 1, actualRPM: 2499, minRPM: nil, maxRPM: nil, targetRPM: nil, mode: .automatic),
        ]
        let model = makeModel(client: client, installer: installer, heartbeat: heartbeat, source: source)
        let fans = await model.readFans()
        #expect(fans?.count == 2)
        #expect(fans?[0].isManual == true && fans?[0].minRPM == 2317)
        #expect(fans?[1].isManual == false && fans?[1].minRPM == nil, "a value the SMC did not return stays nil")
        #expect(client.commands.isEmpty)
        source.error = FakeError()
        #expect(await model.readFans() == nil)
    }

    @Test func setTargetGoesThroughTheClientAndStartsTheHeartbeat() async {
        let model = await ready()
        let outcome = await model.setTarget(fan: 1, rpm: 4000.4)
        #expect(outcome == .applied(fan: 1, rpm: 4000))
        #expect(client.commands == [.setTarget(fan: 1, rpm: 4000)])
        #expect(model.isManualActive && heartbeat.isRunning, "the model's own heartbeat keeps the helper's watchdog fed")
    }

    @Test func setTargetWithoutAnApprovedReachableHelperSendsNothing() async {
        installer.status = .requiresApproval
        let model = makeModel(client: client, installer: installer, heartbeat: heartbeat, source: source)
        #expect(await model.setTarget(fan: 0, rpm: 3000) == .unreachable)
        client.reachable = false
        installer.status = .enabled
        let down = await ready()
        #expect(await down.setTarget(fan: 0, rpm: 3000) == .unreachable)
        #expect(client.commands.isEmpty)
    }

    @Test func nonsenseSpeedsNeverLeaveTheApp() async {
        let model = await ready()
        for rpm in [Double.nan, .infinity, -5, 0] {
            #expect(await model.setTarget(fan: 0, rpm: rpm) == .unreachable)
        }
        #expect(client.commands.isEmpty)
    }

    @Test func helperAnswersAreMappedToOutcomes() async {
        let model = await ready()
        client.result = { _ in FanCommandResult(status: .rejected, reason: "rateLimited", retryAfter: 1) }
        #expect(await model.setTarget(fan: 0, rpm: 3000) == .rejected(reason: "rateLimited"))
        client.result = { _ in FanCommandResult(status: .forcedAutomatic) }
        #expect(await model.setTarget(fan: 0, rpm: 3000) == .forcedAutomatic)
        client.result = { _ in FanCommandResult(status: .failed, reason: "writeFailed") }
        #expect(await model.setTarget(fan: 0, rpm: 3000) == .failed(reason: "writeFailed"))
        #expect(!model.isManualActive, "a failed write ends manual mode locally too")
    }

    @Test func returnAllToAutomaticAnswersAutomaticAndStopsTheHeartbeat() async {
        let model = await ready()
        _ = await model.setTarget(fan: 0, rpm: 3000)
        let outcome = await model.returnAllToAutomatic()
        #expect(outcome == .automatic)
        #expect(client.commands.last == .allAutomatic)
        #expect(!model.isManualActive && !heartbeat.isRunning)
        client.reachable = false
        #expect(await model.returnAllToAutomatic() == .unreachable)
    }

    @Test func aLateSetTargetReplyAfterAReturnToAutomaticIsDropped() async {
        let model = await ready()
        client.holdSetTarget = true
        let pending = Task { await model.setTarget(fan: 0, rpm: 3000) }
        await client.waitUntilHeld()
        _ = await model.returnAllToAutomatic()
        client.releaseHeld()
        #expect(await pending.value == .automatic)
        #expect(!model.isManualActive, "the explicit hand-back wins the race")
    }

    @Test func theBlockingHandBackSendsOnceAndEndsLocalManualMode() async {
        let model = await ready()
        _ = await model.setTarget(fan: 0, rpm: 3000)
        model.returnAllToAutomaticNow()
        #expect(client.blockingAutomatic == 1)
        #expect(!model.isManualActive)
    }

    @Test func aLostHeartbeatAndADroppedConnectionTellThePolicy() async {
        let model = await ready()
        var told: [String?] = []
        model.onManualEnded = { told.append($0) }
        _ = await model.setTarget(fan: 0, rpm: 3000)
        client.heartbeatAnswer = false
        await heartbeat.fire()
        #expect(told.count == 1, "manual ended without a command of ours")
        _ = await model.setTarget(fan: 0, rpm: 3000)
        client.dropConnection()
        await model.drainCallbacks()
        #expect(told.count == 2)
    }

    @Test func ourOwnReturnToAutomaticIsReportedOnceAtMost() async {
        let model = await ready()
        var told = 0
        model.onManualEnded = { _ in told += 1 }
        _ = await model.setTarget(fan: 0, rpm: 3000)
        _ = await model.returnAllToAutomatic()
        #expect(told <= 1)
        _ = await model.returnAllToAutomatic()
        #expect(told <= 1, "nothing was manual: nothing to report")
    }

    @Test func theDriverDoorIsTheSharedModel() {
        #expect(FansFeature.driver is FansModel)
    }
}
