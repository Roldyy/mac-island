import Foundation
import IslandKit
import Testing
@testable import PortKit

/// The camera must never stay on without the user seeing it: the indicator and the 5 minute inactivity close, driven
/// by a fake clock and a recording island. No camera, no AVFoundation, no real timer.
@MainActor
@Suite(.serialized) struct CaptureToolsSafetyTests {
    @MainActor final class Island: CameraIndicatorPoster {
        var posted: [AmbientIndicator] = []
        var withdrawn: [String] = []
        var visible: [String: AmbientIndicator] = [:]
        func post(_ indicator: AmbientIndicator) {
            posted.append(indicator)
            visible[indicator.id] = indicator
        }
        func withdraw(id: String) {
            withdrawn.append(id)
            visible[id] = nil
        }
    }

    /// A clock that only moves when the test says so. `schedule` is what `CameraSafety` receives.
    @MainActor final class Clock {
        struct Job { let id: Int; let due: TimeInterval; let fire: @MainActor () -> Void }
        private(set) var now: TimeInterval = 0
        private var nextID = 0
        private(set) var jobs: [Job] = []
        private(set) var cancelled = 0

        var schedule: CameraSafety.Schedule {
            { [self] delay, fire in
                nextID += 1
                let id = nextID
                jobs.append(Job(id: id, due: now + delay, fire: fire))
                return { [self] in
                    if jobs.contains(where: { $0.id == id }) { cancelled += 1 }
                    jobs.removeAll { $0.id == id }
                }
            }
        }

        func advance(by seconds: TimeInterval) {
            let target = now + seconds
            while let next = jobs.filter({ $0.due <= target }).min(by: { $0.due < $1.due }) {
                now = next.due
                jobs.removeAll { $0.id == next.id }
                next.fire()
            }
            now = target
        }
    }

    final class Preview {
        var closes = 0
    }

    struct Rig {
        let safety: CameraSafety
        let island: Island
        let clock: Clock
        let preview: Preview
    }

    func rig(limit: TimeInterval = CameraSafety.inactivityLimit) -> Rig {
        let island = Island()
        let clock = Clock()
        let preview = Preview()
        let safety = CameraSafety(poster: island, schedule: clock.schedule,
                                  closePreview: { preview.closes += 1 }, limit: limit)
        return Rig(safety: safety, island: island, clock: clock, preview: preview)
    }

    // MARK: Indicator

    @Test func theLimitIsFiveMinutes() {
        #expect(CameraSafety.inactivityLimit == 300)
    }

    @Test func theIndicatorIsAlwaysOnPinnedGreenAndReadable() {
        let indicator = CameraSafety.indicator
        #expect(indicator.id == "capture.camera")
        #expect(indicator.channel == AmbientChannel.alert, "the alert channel has no Settings switch: it cannot be turned off")
        #expect(ClosedIslandSettings.standard.isEnabled(indicator.channel))
        #expect(!AmbientChannel.userChoices.contains(indicator.channel))
        #expect(indicator.channel != AmbientChannel.camera, "not the opt-in channel for other apps' cameras")
        #expect(indicator.status == .success && indicator.symbol == "video.fill")
        #expect(indicator.isReadable, "a state that means something on its own is drawn")
        #expect(indicator.isPinned, "never rotated away")
        #expect(indicator.label?.contains("Caméra active") == true, "colour is not the only signal")
        #expect(indicator.accessibilityLabel().contains("Caméra active"))
    }

    @Test func theIndicatorReallyLandsInAWingOfTheClosedIsland() {
        let content = ClosedIslandLayout.resolve([CameraSafety.indicator], settings: .standard)
        let shown = (content.leading + content.trailing).map(\.id)
        #expect(shown == ["capture.camera"])
        // Even with every user channel switched off, the alert still shows.
        var quiet = ClosedIslandSettings.standard
        quiet.enabled = []
        let still = ClosedIslandLayout.resolve([CameraSafety.indicator], settings: quiet)
        #expect((still.leading + still.trailing).map(\.id) == ["capture.camera"])
    }

    @Test func aSessionPostsTheIndicatorAndEndingItWithdrawsIt() {
        let r = rig()
        r.safety.sessionChanged(active: true)
        #expect(r.island.visible["capture.camera"] == CameraSafety.indicator)
        #expect(r.island.posted.count == 1)
        r.safety.sessionChanged(active: false)
        #expect(r.island.visible.isEmpty)
        #expect(r.island.withdrawn == ["capture.camera"])
        #expect(r.preview.closes == 0, "a normal close is not a timeout")
    }

    @Test func resetWithdrawsTheIndicatorEvenIfTheServiceNeverSaidSo() {
        let r = rig()
        r.safety.sessionChanged(active: true)
        r.safety.reset()
        #expect(r.island.visible.isEmpty && !r.safety.isSessionActive)
        #expect(r.clock.jobs.isEmpty, "and the timer is gone")
    }

    // MARK: Inactivity auto-close, fake clock

    @Test func theTimerArmsWhenTheSessionStartsAndFiresAtFiveMinutesNotBefore() {
        let r = rig()
        r.safety.sessionChanged(active: true)
        #expect(r.clock.jobs.count == 1 && r.clock.jobs[0].due == 300)
        r.clock.advance(by: 299.9)
        #expect(r.preview.closes == 0 && r.island.visible["capture.camera"] != nil)
        r.clock.advance(by: 0.2)
        #expect(r.preview.closes == 1, "closed once")
        #expect(r.island.visible.isEmpty, "the indicator goes with it")
        #expect(r.clock.jobs.isEmpty)
        r.clock.advance(by: 3600)
        #expect(r.preview.closes == 1, "and never fires again")
    }

    @Test func anyActivityStartsTheFiveMinutesOver() {
        let r = rig()
        r.safety.sessionChanged(active: true)
        r.clock.advance(by: 200)
        r.safety.noteActivity()
        r.clock.advance(by: 200)
        #expect(r.preview.closes == 0, "400 s in, but 200 s since the last touch")
        r.clock.advance(by: 99)
        #expect(r.preview.closes == 0)
        r.clock.advance(by: 1)
        #expect(r.preview.closes == 1)
        #expect(r.clock.now == 500)
    }

    @Test func manyTouchesLeaveExactlyOneTimerPending() {
        let r = rig()
        r.safety.sessionChanged(active: true)
        for _ in 0..<50 { r.safety.noteActivity() }
        #expect(r.clock.jobs.count == 1)
        #expect(r.clock.cancelled == 50, "each touch cancelled the previous timer")
    }

    @Test func activityWithoutASessionArmsNothing() {
        let r = rig()
        r.safety.noteActivity()
        #expect(r.clock.jobs.isEmpty && r.island.posted.isEmpty)
    }

    @Test func endingTheSessionCancelsTheTimer() {
        let r = rig()
        r.safety.sessionChanged(active: true)
        r.safety.sessionChanged(active: false)
        #expect(r.clock.jobs.isEmpty)
        r.clock.advance(by: 10_000)
        #expect(r.preview.closes == 0, "a closed preview is never closed again by a stale timer")
    }

    @Test func aRestartedSessionGetsAFreshFullTimer() {
        let r = rig()
        r.safety.sessionChanged(active: true)
        r.clock.advance(by: 250)
        r.safety.sessionChanged(active: false)
        r.safety.sessionChanged(active: true)
        #expect(r.clock.jobs.count == 1 && r.clock.jobs[0].due == 550)
        r.clock.advance(by: 299)
        #expect(r.preview.closes == 0)
        r.clock.advance(by: 1)
        #expect(r.preview.closes == 1)
    }

    @Test func reportingActiveTwiceStillLeavesOneTimerAndOneIndicator() {
        let r = rig()
        r.safety.sessionChanged(active: true)
        r.safety.sessionChanged(active: true)
        #expect(r.clock.jobs.count == 1 && r.island.visible.count == 1)
    }

    @Test func aPreviewThatIgnoresTheCloseStillLosesItsIndicatorAndTimer() {
        let r = rig()
        r.safety.sessionChanged(active: true)
        r.clock.advance(by: 300)
        #expect(r.preview.closes == 1, "the close was asked")
        #expect(!r.safety.isSessionActive && r.island.visible.isEmpty && r.clock.jobs.isEmpty)
    }

    // MARK: The service's hooks (source gates: the real service needs a camera)

    @Test func theServiceReportsEverySessionBirthAndReleaseAndEveryTouch() throws {
        let text = try CaptureToolsLaneTests.source("Sources/PortKit/Services/QuickTools/CameraPreviewService.swift")
        func count(_ needle: String) -> Int { text.components(separatedBy: needle).count - 1 }
        #expect(count("onSessionChange?(true)") == 1 && count("onSessionChange?(false)") == 1)
        let born = try #require(text.range(of: "self.session = session\n        onSessionChange?(true)"))
        let released = try #require(text.range(of: "self.session = nil\n        onSessionChange?(false)"))
        #expect(born.lowerBound < released.lowerBound)
        // The release comes before the queued stopRunning, in the same main-thread turn as `hide()`.
        #expect(text.contains("onSessionChange?(false)\n        sessionQueue.async {"))
        #expect(count("noteActivity()") >= 4, "key, click inside, camera pick, hover (view)")
        let view = try CaptureToolsLaneTests.source("Sources/PortKit/UI/CameraPreview/CameraPreviewView.swift")
        #expect(view.contains("service.noteActivity()"))
    }

    @Test func everyWayOfClosingThePreviewGoesThroughHideAndHideReleasesTheSession() throws {
        let text = try CaptureToolsLaneTests.source("Sources/PortKit/Services/QuickTools/CameraPreviewService.swift")
        let hide = try #require(text.range(of: "    func hide() {"))
        let body = String(text[hide.lowerBound...].prefix(400))
        #expect(body.contains("stopSession()") && body.contains("panel?.orderOut(nil)") && body.contains("state = .idle"))
        // Escape, outside click, activation of another app, device loss: all call hide() or stopSession().
        let escape = try #require(text.range(of: "if event.keyCode == UInt16(kVK_Escape) {"))
        #expect(String(text[escape.lowerBound...].prefix(80)).contains("self.hide()"))
        #expect(text.contains("func suspend() {\n        hotkey.unregister()\n        hide()\n    }"), "the registry stop = hide()")
        // The quit hook waits for the capture queue so the camera is released before the process ends.
        #expect(text.contains("func shutdownForQuit() {\n        hide()\n        sessionQueue.sync {}\n    }"))
        let bridge = try CaptureToolsLaneTests.source("Sources/PortKit/Bridge/CaptureTools.swift")
        #expect(bridge.contains("NSApplication.willTerminateNotification"))
        #expect(bridge.contains("CameraPreviewService.shared.shutdownForQuit()"))
    }
}
