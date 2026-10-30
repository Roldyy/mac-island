import Foundation
import Testing
@testable import AudioFeature

@MainActor @Suite struct MixerModelTests {
    let temp = TempDefaults()
    func make(procs: [AudioProcess] = [], output: String? = "out1", positions: [String: Double] = [:],
              ready: Flag = Flag(true))
        -> (MixerModel, FakeEngine, FakeAudioSystem, AudioSettings) {
        let sys = FakeAudioSystem()
        sys.processList = procs
        sys.defaults[.output] = output
        let engine = FakeEngine()
        let d = temp.defaults
        let settings = AudioSettings(defaults: d)
        for (k, v) in positions { settings.setPosition(v, for: k) }
        let m = MixerModel(engine: engine, system: sys, settings: settings, ownPID: 1,
                           isCaptureReady: { ready.value })
        return (m, engine, sys, settings)
    }

    @Test func listsRunningAppsGroupedByBundleAndSkipsSelfAndSilent() {
        let (m, _, _, _) = make(procs: [
            proc(10, pid: 100, "com.b"), proc(11, pid: 101, "com.b"),
            proc(12, pid: 102, "com.a"), proc(13, pid: 1, "com.self"),
            proc(14, pid: 103, "com.quiet", running: false), proc(15, pid: 104, ""),
        ])
        m.refresh()
        #expect(m.apps.map(\.id) == ["com.a", "com.b"])
        #expect(m.apps.last?.processIDs == [10, 11])
    }

    @Test func untouchedAppGetsNoTap() {
        let (m, e, _, _) = make(procs: [proc(10, pid: 100, "com.a")])
        m.refresh()
        #expect(e.starts.isEmpty)
        #expect(m.hasLiveTaps == false)
    }

    @Test func movingSliderStartsTapThenUpdatesGainThenReleasesAtUnity() {
        let (m, e, _, _) = make(procs: [proc(10, pid: 100, "com.a")])
        m.refresh()
        m.setPosition(0.5, for: "com.a")
        #expect(e.starts == [.init(app: "com.a", processes: [10], output: "out1", gain: 0.25)])
        m.setPosition(0.7, for: "com.a")
        #expect(e.starts.count == 1)
        #expect(e.gains.last?.app == "com.a")
        #expect(abs((e.gains.last?.gain ?? 0) - 0.49) < 1e-6)
        m.setPosition(1.0, for: "com.a")
        #expect(e.stops == ["com.a"])
        #expect(m.hasLiveTaps == false)
    }

    @Test func muteSilencesAndUnmuteRestores() {
        let (m, e, _, _) = make(procs: [proc(10, pid: 100, "com.a")])
        m.refresh()
        m.setMuted(true, for: "com.a")
        #expect(e.starts.last?.gain == 0)
        m.setMuted(false, for: "com.a")
        #expect(e.stops == ["com.a"]) // back to 1.0: tap released
    }

    @Test func mutedAtHalfVolumeRestoresHalfGain() {
        let (m, e, _, _) = make(procs: [proc(10, pid: 100, "com.a")])
        m.refresh()
        m.setPosition(0.5, for: "com.a")
        m.setMuted(true, for: "com.a")
        #expect(e.gains.last?.gain == 0)
        m.setMuted(false, for: "com.a")
        #expect(e.gains.last?.gain == 0.25)
    }

    @Test func savedPositionAppliesWhenAppAppears() {
        let (m, e, _, _) = make(procs: [proc(10, pid: 100, "com.a")], positions: ["com.a": 0.5])
        m.refresh()
        #expect(e.starts == [.init(app: "com.a", processes: [10], output: "out1", gain: 0.25)])
    }

    @Test func importedZeroPositionBecomesAnExplicitVisibleMutedRow() {
        // Migrated data holds 0.0 for apps the user never muted on purpose: show it as muted.
        let (m, e, _, s) = make(procs: [proc(10, pid: 100, "com.a", running: false)], positions: ["com.a": 0])
        m.refresh()
        #expect(m.apps.map(\.id) == ["com.a"])
        #expect(m.apps.first?.isMuted == true)
        #expect(m.apps.first?.position == 1)
        #expect(s.mutedApps == ["com.a"])
        #expect(s.appPositions["com.a"] == 1)
        m.setMuted(false, for: "com.a") // one click to undo
        #expect(m.apps.first?.isMuted == false)
        #expect(e.live.isEmpty)
        #expect(m.hasLiveTaps == false)
    }

    @Test func controlledAppIsListedEvenWhenSilent() {
        let (m, _, _, _) = make(procs: [proc(10, pid: 100, "com.a", running: false),
                                        proc(11, pid: 101, "com.b", running: false)],
                                positions: ["com.a": 0.5])
        m.refresh()
        #expect(m.apps.map(\.id) == ["com.a"])
    }

    @Test func noTapAndNoPromptUntilCaptureIsReady() {
        let ready = Flag(false)
        let (m, e, _, _) = make(procs: [proc(10, pid: 100, "com.a")], positions: ["com.a": 0.5], ready: ready)
        m.refresh()
        m.setPosition(0.4, for: "com.a")
        m.setMuted(true, for: "com.a")
        #expect(e.starts.isEmpty)
        #expect(m.hasLiveTaps == false)
        #expect(m.failedTapCount == 0)
        #expect(m.apps.map(\.id) == ["com.a"]) // the row stays, the wanted state is kept
        ready.value = true
        m.refresh()
        #expect(e.starts.count == 1)
        #expect(e.starts.first?.gain == 0)
    }

    @Test func losingCaptureReleasesLiveTaps() {
        let ready = Flag(true)
        let (m, e, _, _) = make(procs: [proc(10, pid: 100, "com.a")], ready: ready)
        m.refresh()
        m.setPosition(0.5, for: "com.a")
        #expect(m.hasLiveTaps)
        ready.value = false
        m.refresh()
        #expect(e.live.isEmpty)
    }

    @Test func appExitReleasesTapAndDropsRow() {
        let (m, e, sys, _) = make(procs: [proc(10, pid: 100, "com.a")])
        m.refresh()
        m.setPosition(0.5, for: "com.a")
        sys.processList = []
        m.refresh()
        #expect(e.stops == ["com.a"])
        #expect(m.apps.isEmpty)
    }

    @Test func pausedAppWithLiveTapStaysListed() {
        let (m, e, sys, _) = make(procs: [proc(10, pid: 100, "com.a")])
        m.refresh()
        m.setPosition(0.5, for: "com.a")
        sys.processList = [proc(10, pid: 100, "com.a", running: false)]
        m.refresh()
        #expect(m.apps.map(\.id) == ["com.a"])
        #expect(e.stops.isEmpty)
    }

    @Test func newHelperProcessRestartsTapWithFullSet() {
        let (m, e, sys, _) = make(procs: [proc(10, pid: 100, "com.a")])
        m.refresh()
        m.setPosition(0.5, for: "com.a")
        sys.processList = [proc(10, pid: 100, "com.a"), proc(11, pid: 101, "com.a")]
        m.refresh()
        #expect(e.stops == ["com.a"])
        #expect(e.starts.last?.processes == [10, 11])
    }

    @Test func outputDeviceChangeRebuildsLiveTaps() {
        let (m, e, sys, _) = make(procs: [proc(10, pid: 100, "com.a")])
        m.refresh()
        m.setPosition(0.5, for: "com.a")
        sys.defaults[.output] = "out2"
        m.refresh()
        #expect(e.starts.last?.output == "out2")
        #expect(e.stops == ["com.a"])
    }

    @Test func noOutputDeviceReleasesEverything() {
        let (m, e, sys, _) = make(procs: [proc(10, pid: 100, "com.a")])
        m.refresh()
        m.setPosition(0.5, for: "com.a")
        sys.defaults[.output] = nil
        m.refresh()
        #expect(e.live.isEmpty)
    }

    @Test func tapFailureLeavesAppUntouchedAndIsNotRetriedEveryRefresh() {
        let (m, e, _, _) = make(procs: [proc(10, pid: 100, "com.a")])
        e.failStart = true
        m.refresh()
        m.setPosition(0.5, for: "com.a")
        #expect(m.failedTapCount == 1)
        #expect(m.apps.first?.isLive == false)
        m.refresh(); m.refresh()
        #expect(m.failedTapCount == 1)
    }

    @Test func stopTearsEverythingDownAndIsIdempotent() {
        let (m, e, _, _) = make(procs: [proc(10, pid: 100, "com.a")])
        m.refresh()
        m.setPosition(0.5, for: "com.a")
        m.stop(); m.stop()
        #expect(e.live.isEmpty)
        #expect(m.hasLiveTaps == false)
    }

    @Test func positionsPersist() {
        let (m, _, _, s) = make(procs: [proc(10, pid: 100, "com.a")])
        m.refresh()
        m.setPosition(0.4, for: "com.a")
        #expect(s.appPositions["com.a"] == 0.4)
    }
}
