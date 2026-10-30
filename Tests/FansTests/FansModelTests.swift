import FanShared
import ServiceManagement
import Testing
@testable import FansFeature

@Suite @MainActor struct FansModelTests {
    let client = FakeHelperClient()
    let installer = FakeInstaller()
    let heartbeat = FakeHeartbeat()
    let source = FakeReadingSource()

    private func ready() async -> FansModel {
        let model = makeModel(client: client, installer: installer, heartbeat: heartbeat, source: source)
        model.start()
        await model.connectTask?.value
        await model.refreshReadings()
        return model
    }

    // MARK: - Monitoring (no helper needed)

    @Test func readingsComeFromTheReadOnlySourceWithoutTheHelper() async {
        installer.status = .notRegistered
        let model = makeModel(client: client, installer: installer, heartbeat: heartbeat, source: source)
        await model.refreshReadings()
        #expect(model.readings.count == 2)
        #expect(model.readings[1].actualRPM == 2499)
        #expect(model.readError == nil)
        #expect(model.range(for: 0) == 2317...7826)
        #expect(model.targets[1] == 2502)
        #expect(client.commands.isEmpty)
    }

    @Test func aReadFailureIsShownNotHidden() async {
        source.error = FakeError()
        let model = makeModel(client: client, installer: installer, heartbeat: heartbeat, source: source)
        await model.refreshReadings()
        #expect(model.readings.isEmpty)
        #expect(model.readError != nil)
    }

    // MARK: - Installation

    @Test func startNeverRegistersTheHelper() async {
        installer.status = .notRegistered
        let model = makeModel(client: client, installer: installer, heartbeat: heartbeat, source: source)
        model.start()
        await model.connectTask?.value
        #expect(installer.registerCount == 0)
        #expect(installer.openSettingsCount == 0)
        #expect(!model.manualAvailable)
    }

    @Test func installAndApprovalAreExplicitUserActions() {
        installer.status = .notRegistered
        let model = makeModel(client: client, installer: installer, heartbeat: heartbeat, source: source)
        model.installHelper()
        #expect(installer.registerCount == 1)
        #expect(model.installStatus == .requiresApproval)
        model.openLoginItems()
        #expect(installer.openSettingsCount == 1)
    }

    @Test func registerErrorIsReported() {
        installer.status = .notRegistered
        installer.registerError = FakeError()
        let model = makeModel(client: client, installer: installer, heartbeat: heartbeat, source: source)
        model.installHelper()
        #expect(model.statusMessage != nil)
        #expect(model.installStatus == .notRegistered)
    }

    @Test func statusMapsEverySMAppServiceCase() {
        #expect(HelperInstallStatus(SMAppService.Status.notRegistered) == .notRegistered)
        #expect(HelperInstallStatus(SMAppService.Status.requiresApproval) == .requiresApproval)
        #expect(HelperInstallStatus(SMAppService.Status.enabled) == .enabled)
        #expect(HelperInstallStatus(SMAppService.Status.notFound) == .notFound)
    }

    // MARK: - Manual control gate

    @Test func manualIsDisabledUnlessApprovedAndReachable() async {
        for status in [HelperInstallStatus.notRegistered, .requiresApproval, .notFound] {
            installer.status = status
            let model = await ready()
            #expect(!model.manualAvailable)
            model.targets[0] = 4000
            await model.commitTarget(fan: 0)
            #expect(client.commands.isEmpty)
            model.stop()
        }
        installer.status = .enabled
        client.reachable = false
        let unreachable = await ready()
        #expect(!unreachable.manualAvailable)
    }

    @Test func commitSendsAClampedTargetAndStartsTheHeartbeat() async {
        let model = await ready()
        #expect(model.manualAvailable)
        #expect(!heartbeat.isRunning)
        model.targets[0] = 99_999
        await model.commitTarget(fan: 0)
        #expect(client.commands == [.setTarget(fan: 0, rpm: 7826)])
        #expect(model.manualActive)
        #expect(heartbeat.isRunning)
        #expect(heartbeat.interval == FanHelperContract.heartbeatInterval)
    }

    @Test func nonFiniteSliderValueIsNeverSent() async {
        let model = await ready()
        model.targets[0] = .nan
        await model.commitTarget(fan: 0)
        #expect(client.commands.isEmpty)
    }

    @Test func returnToAutomaticStopsTheHeartbeat() async {
        let model = await ready()
        model.targets[0] = 4000
        await model.commitTarget(fan: 0)
        await model.returnToAutomatic()
        #expect(client.commands.last == .allAutomatic)
        #expect(!model.manualActive)
        #expect(!heartbeat.isRunning)
    }

    @Test func heartbeatRefusedMeansTheHelperWentAutomatic() async {
        let model = await ready()
        model.targets[0] = 4000
        await model.commitTarget(fan: 0)
        await heartbeat.fire()
        #expect(client.heartbeats == 1)
        #expect(model.manualActive)
        client.heartbeatAnswer = false
        await heartbeat.fire()
        #expect(!model.manualActive)
        #expect(!heartbeat.isRunning)
    }

    @Test func thermalOverrideFromTheHelperIsShown() async {
        client.result = { _ in FanCommandResult(status: .forcedAutomatic, fan: 0, reason: "thermal") }
        let model = await ready()
        model.targets[0] = 4000
        await model.commitTarget(fan: 0)
        #expect(!model.manualActive)
        #expect(!heartbeat.isRunning)
        #expect(model.statusMessage?.contains("Température") == true)
    }

    @Test func leftoverManualModeIsSentBackToAutomaticOnConnect() async {
        client.state = FanState(protocolVersion: 1, fans: [], maxTemperatureCelsius: 60, manualActive: true)
        _ = await ready()
        #expect(client.commands == [.allAutomatic])
    }

    @Test func droppedConnectionClearsManualState() async {
        let model = await ready()
        model.targets[0] = 4000
        await model.commitTarget(fan: 0)
        client.dropConnection()
        await model.drainCallbacks()
        #expect(!model.manualActive)
        #expect(!model.helperReachable)
        #expect(!heartbeat.isRunning)
    }

    // MARK: - Everything that ends manual mode sends automatic

    @Test func stopSendsAutomaticOnceAndIsIdempotent() async {
        let model = await ready()
        model.targets[0] = 4000
        await model.commitTarget(fan: 0)
        model.stop()
        model.stop()
        #expect(client.blockingAutomatic == 1)
        #expect(!model.manualActive)
        #expect(!heartbeat.isRunning)
        #expect(client.disconnects == 1)
    }

    @Test func stopWithoutStartDoesNothing() {
        let model = makeModel(client: client, installer: installer, heartbeat: heartbeat, source: source)
        model.stop()
        #expect(client.blockingAutomatic == 0)
    }

    @Test func startIsIdempotent() async {
        let model = makeModel(client: client, installer: installer, heartbeat: heartbeat, source: source)
        model.start()
        let first = model.connectTask
        model.start()
        #expect(model.connectTask == first)
        await model.connectTask?.value
    }

    @Test func closingTheTabInManualModeSendsAutomatic() async {
        let model = await ready()
        model.targets[1] = 5000
        await model.commitTarget(fan: 1)
        await model.viewClosed()
        #expect(client.commands.last == .allAutomatic)
        #expect(!model.manualActive)
    }

    @Test func closingTheTabInAutomaticModeSendsNothing() async {
        let model = await ready()
        await model.viewClosed()
        #expect(client.commands.isEmpty)
    }

    @Test func deinitInManualModeSendsAutomatic() async {
        var model: FansModel? = await ready()
        model?.targets[0] = 4000
        await model?.commitTarget(fan: 0)
        #expect(client.blockingAutomatic == 0)
        model = nil
        #expect(client.blockingAutomatic == 1)
    }

    @Test func deinitInAutomaticModeSendsNothing() async {
        var model: FansModel? = await ready()
        #expect(model?.manualActive == false)
        model = nil
        #expect(client.blockingAutomatic == 0)
    }
}

@Suite struct ReconnectBackoffTests {
    @Test func doublesUpToTheCapAndResets() {
        var b = ReconnectBackoff(initial: 0.5, maximum: 30)
        let delays = (0..<9).map { _ in b.next() }
        #expect(delays == [0.5, 1, 2, 4, 8, 16, 30, 30, 30])
        b.reset()
        #expect(b.next() == 0.5)
    }
}
