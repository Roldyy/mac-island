import Foundation
import Testing
@testable import AudioFeature

@MainActor @Suite struct AudioFeatureModelTests {
    let temp = TempDefaults()
    func make(hasPlist: Bool = true, probe: Int32 = 0)
        -> (AudioFeatureModel, FakeAudioSystem, FakeEngine) {
        let sys = FakeAudioSystem()
        sys.deviceList = [out("o1")]
        sys.defaults[.output] = "o1"
        sys.processList = [proc(10, pid: 100, "com.a")]
        let engine = FakeEngine()
        let m = AudioFeatureModel(system: sys, engine: engine, settings: AudioSettings(defaults: temp.defaults),
                                  hasUsageDescription: { hasPlist }, probe: { probe })
        return (m, sys, engine)
    }

    @Test func startAndStopAreIdempotent() {
        let (m, sys, e) = make()
        m.start(); m.start()
        #expect(sys.startListeningCount == 1)
        m.stop(); m.stop()
        #expect(sys.stopListeningCount == 1)
        #expect(e.stopAllCount == 1)
    }

    @Test func hiddenWithoutTapsIgnoresProcessEvents() {
        let (m, sys, _) = make()
        m.start()
        sys.emit(.processesChanged)
        #expect(sys.processesCalls == 0)
    }

    @Test func visibleTabRefreshesOnEvents() {
        let (m, sys, _) = make()
        m.start()
        m.setVisible(true)
        let before = sys.processesCalls
        #expect(before >= 1)
        sys.emit(.processesChanged)
        #expect(sys.processesCalls == before + 1)
        m.setVisible(false)
    }

    @Test func liveTapKeepsListeningWhileHidden() {
        let (m, sys, e) = make()
        m.start()
        m.setVisible(true)
        m.requestPermission()
        m.mixer.setPosition(0.5, for: "com.a")
        m.setVisible(false)
        sys.processList = []
        sys.emit(.processesChanged)
        #expect(e.stops == ["com.a"])
    }

    @Test func stopReleasesTaps() {
        let (m, _, e) = make()
        m.start()
        m.setVisible(true)
        m.requestPermission()
        m.mixer.setPosition(0.5, for: "com.a")
        m.stop()
        #expect(e.live.isEmpty)
    }

    @Test func noTapUntilTheUserGrantedCapture() {
        let (m, _, e) = make()
        m.start()
        m.setVisible(true)
        m.mixer.setPosition(0.5, for: "com.a")
        #expect(e.live.isEmpty)
        #expect(m.mixer.failedTapCount == 0)
        m.requestPermission()
        #expect(e.live == ["com.a"])
    }

    @Test func refusedPermissionKeepsTapsOff() {
        let (m, _, e) = make(probe: -50)
        m.start()
        m.setVisible(true)
        m.requestPermission()
        m.mixer.setPosition(0.5, for: "com.a")
        #expect(e.live.isEmpty)
    }

    @Test func permissionNeverProbedAtLaunch() {
        var probed = 0
        let sys = FakeAudioSystem()
        let m = AudioFeatureModel(system: sys, engine: FakeEngine(), settings: AudioSettings(defaults: temp.defaults),
                                  hasUsageDescription: { true }, probe: { probed += 1; return 0 })
        m.start(); m.setVisible(true)
        #expect(probed == 0)
        #expect(m.permission == .notChecked)
        m.requestPermission()
        #expect(probed == 1)
        #expect(m.permission == .ready)
    }

    @Test func requestDoesNothingWithoutBundle() {
        var probed = 0
        let m = AudioFeatureModel(system: FakeAudioSystem(), engine: FakeEngine(),
                                  settings: AudioSettings(defaults: temp.defaults),
                                  hasUsageDescription: { false }, probe: { probed += 1; return 0 })
        m.requestPermission()
        #expect(probed == 0)
        #expect(m.permission == .needsBundledApp)
    }
}
