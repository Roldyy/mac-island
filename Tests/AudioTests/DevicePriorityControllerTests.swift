import Foundation
import Testing
@testable import AudioFeature

@MainActor @Suite struct DevicePriorityControllerTests {
    func make(priority: [String] = ["a", "b", "c"], current: String? = "c",
              devices: [AudioDeviceInfo] = [out("b"), out("c")])
        -> (DevicePriorityController, FakeAudioSystem, MutableClock, AudioSettings) {
        let sys = FakeAudioSystem()
        sys.deviceList = devices
        sys.defaults[.output] = current
        let settings = AudioSettings(defaults: makeDefaults())
        settings.setPriority(priority, for: .output)
        let clock = MutableClock()
        let c = DevicePriorityController(system: sys, settings: settings, now: { clock.date }, manualGrace: 10)
        return (c, sys, clock, settings)
    }

    @Test func startSelectsBestAvailable() {
        let (c, sys, _, _) = make()
        c.start()
        #expect(sys.setCalls.map(\.uid) == ["b"])
        #expect(sys.defaults[.output] == "b")
    }

    @Test func startAndStopAreIdempotent() {
        let (c, sys, _, _) = make()
        c.start(); c.start()
        #expect(sys.startListeningCount == 1)
        c.stop(); c.stop()
        #expect(sys.stopListeningCount == 1)
        #expect(c.isRunning == false)
    }

    @Test func higherPriorityDeviceAppearingTakesOver() {
        let (c, sys, _, _) = make(current: "b", devices: [out("b")])
        c.start()
        #expect(sys.setCalls.isEmpty)
        sys.deviceList.append(out("a"))
        sys.emit(.devicesChanged)
        #expect(sys.setCalls.map(\.uid) == ["a"])
    }

    @Test func currentDeviceDisappearingFallsToNext() {
        let (c, sys, _, _) = make(current: "a", devices: [out("a"), out("b"), out("c")])
        c.start()
        sys.deviceList.removeAll { $0.uid == "a" }
        sys.defaults[.output] = "c" // macOS fell back by itself
        sys.emit(.devicesChanged)
        #expect(sys.setCalls.map(\.uid) == ["b"])
    }

    @Test func manualChangeIsNotFoughtInsideGrace() {
        let (c, sys, clock, _) = make(current: "b", devices: [out("a"), out("b"), out("c")])
        c.start()
        #expect(sys.setCalls.map(\.uid) == ["a"])
        // The user picks c by hand.
        sys.defaults[.output] = "c"
        sys.emit(.defaultChanged(.output))
        clock.advance(3)
        sys.emit(.devicesChanged)
        #expect(sys.setCalls.count == 1)
        // Later device event: priority applies again.
        clock.advance(20)
        sys.emit(.devicesChanged)
        #expect(sys.setCalls.map(\.uid) == ["a", "a"])
    }

    @Test func ownChangeEchoIsNotTreatedAsManual() {
        let (c, sys, clock, _) = make(current: "c", devices: [out("a"), out("c")])
        c.start() // selects a, the HAL echoes defaultChanged
        sys.deviceList.append(out("b"))
        clock.advance(1)
        sys.defaults[.output] = "c"
        sys.emit(.devicesChanged) // not within a manual window: a is still best, c is current
        #expect(sys.setCalls.map(\.uid) == ["a", "a"])
    }

    @Test func inputAndOutputAreIndependent() {
        let (c, sys, _, _) = make(priority: [], current: nil, devices: [out("o1"), inp("i1"), inp("i2")])
        c.setPriority(["i2", "i1"], for: .input)
        sys.defaults[.input] = "i1"
        c.start()
        #expect(sys.setCalls.map(\.uid) == ["i2"])
        #expect(sys.setCalls.first?.direction == .input)
    }

    @Test func setPriorityPersistsAndReevaluates() {
        let (c, sys, _, settings) = make(priority: [], current: "c", devices: [out("b"), out("c")])
        c.start()
        #expect(sys.setCalls.isEmpty)
        c.setPriority(["b", "c"], for: .output)
        #expect(settings.priority(for: .output) == ["b", "c"])
        #expect(sys.setCalls.map(\.uid) == ["b"])
    }

    @Test func stoppedControllerIgnoresEvents() {
        let (c, sys, _, _) = make()
        c.start(); c.stop()
        let n = sys.setCalls.count
        c.handle(.devicesChanged)
        #expect(sys.setCalls.count == n)
    }
}
