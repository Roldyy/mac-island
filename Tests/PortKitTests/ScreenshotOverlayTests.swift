import AppKit
import Foundation
import Testing
@testable import PortKit

/// Lane W4-A: the rules that take a full-screen capture overlay off the screen. A private `NotificationCenter` and a
/// fake clock stand in for AppKit: no window is ever created here.
@MainActor
@Suite(.serialized) struct ScreenshotOverlayTests {
    final class Clock {
        var scheduled: [(delay: TimeInterval, block: () -> Void, cancelled: Box<Bool>)] = []
        var schedule: ScreenshotOverlayGuard.Schedule {
            { [self] delay, block in
                let cancelled = Box(false)
                scheduled.append((delay, block, cancelled))
                return { cancelled.value = true }
            }
        }
        /// Runs every timer that was not cancelled.
        func fire() { for entry in scheduled where !entry.cancelled.value { entry.block() } }
        var live: Int { scheduled.filter { !$0.cancelled.value }.count }
    }

    struct Rig {
        let center = NotificationCenter()
        let clock = Clock()
        let reasons = Box<[ScreenshotOverlayGuard.Reason]>([])
        let overlay: ScreenshotOverlayGuard
        init() {
            let center = center, clock = clock, reasons = reasons
            overlay = ScreenshotOverlayGuard(center: center, schedule: clock.schedule) { reason in
                reasons.value.append(reason)
            }
        }
    }

    // MARK: The rule table

    @Test func theRuleTableIsEscapeDisplayChangeDeactivationAndSixtySeconds() {
        #expect(ScreenshotOverlayGuard.timeout == 60)
        #expect(ScreenshotOverlayGuard.reason(forKeyCode: 53) == .escape)
        for code: UInt16 in [0, 36, 49, 48, 51, 123, 124] {
            #expect(ScreenshotOverlayGuard.reason(forKeyCode: code) == nil, "\(code)")
        }
        let reasons: [ScreenshotOverlayGuard.Reason] = [.escape, .displayChange, .appDeactivated, .timeout]
        #expect(Set(reasons.map { "\($0)" }).count == 4)
    }

    @Test func theTimerIsSixtySecondsByDefault() {
        let clock = Clock()
        let overlay = ScreenshotOverlayGuard(center: NotificationCenter(), schedule: clock.schedule) { _ in }
        overlay.start()
        #expect(clock.scheduled.map(\.delay) == [60])
        overlay.stop()
    }

    // MARK: Each way out

    @Test func escapeClosesTheOverlayOnce() {
        let r = Rig()
        r.overlay.start()
        #expect(r.overlay.handleKey(36) == false, "return is not a way out")
        #expect(r.reasons.value.isEmpty)
        #expect(r.overlay.handleKey(53))
        #expect(r.reasons.value == [.escape])
        #expect(r.overlay.handleKey(53) == false, "closed: nothing fires twice")
        #expect(r.reasons.value == [.escape])
        #expect(!r.overlay.isArmed)
    }

    @Test func aDisplayChangeClosesTheOverlay() {
        let r = Rig()
        r.overlay.start()
        r.center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(r.reasons.value == [.displayChange])
        #expect(r.overlay.closedBy == .displayChange)
        #expect(r.clock.live == 0, "the timer went with it")
    }

    @Test func losingTheFocusClosesTheOverlayOnlyOnceItIsOnScreen() {
        let r = Rig()
        r.overlay.start()
        // The island closing or the settings window handing over the focus while the capture starts.
        r.center.post(name: NSApplication.didResignActiveNotification, object: nil)
        #expect(r.reasons.value.isEmpty, "not armed yet: the start is not cancelled by its own focus change")
        r.overlay.armDeactivation()
        r.overlay.armDeactivation()
        r.center.post(name: NSApplication.didResignActiveNotification, object: nil)
        #expect(r.reasons.value == [.appDeactivated], "armed once, fired once")
    }

    @Test func sixtySecondsWithoutAnOutcomeClosesTheOverlay() {
        let r = Rig()
        r.overlay.start()
        #expect(r.clock.live == 1)
        r.clock.fire()
        #expect(r.reasons.value == [.timeout])
        #expect(!r.overlay.isArmed)
    }

    // MARK: Disarming

    @Test func stoppingRemovesEveryObserverAndTheTimer() {
        let r = Rig()
        r.overlay.start()
        r.overlay.armDeactivation()
        r.overlay.stop()
        r.center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        r.center.post(name: NSApplication.didResignActiveNotification, object: nil)
        r.clock.fire()
        #expect(r.reasons.value.isEmpty, "a finished session is never closed a second time")
        #expect(r.clock.live == 0)
        #expect(r.overlay.handleKey(53) == false)
        r.overlay.stop()  // idempotent
    }

    @Test func startIsIdempotentAndAFirstReasonWins() {
        let r = Rig()
        r.overlay.start()
        r.overlay.start()
        #expect(r.clock.scheduled.count == 1, "one timer")
        r.center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        r.center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        r.clock.fire()
        #expect(r.reasons.value == [.displayChange])
    }

    @Test func aDeallocatedGuardLeavesNoObserverBehind() {
        let center = NotificationCenter()
        let clock = Clock()
        let reasons = Box<[ScreenshotOverlayGuard.Reason]>([])
        var overlay: ScreenshotOverlayGuard? = ScreenshotOverlayGuard(center: center, schedule: clock.schedule) {
            reasons.value.append($0)
        }
        overlay?.start()
        overlay?.armDeactivation()
        overlay = nil
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        center.post(name: NSApplication.didResignActiveNotification, object: nil)
        #expect(reasons.value.isEmpty)
    }

    // MARK: The controller really uses the guard

    @Test func theSelectionControllerArmsTheGuardAtBeginAndDisarmsAtFinish() throws {
        let text = try String(contentsOf: PortSourceScrubTests.portKit
            .appendingPathComponent("Services/QuickTools/ScreenshotSelectionController.swift"), encoding: .utf8)
        #expect(text.contains("overlayGuard.start()"), "armed when the session begins")
        #expect(text.contains("overlayGuard?.armDeactivation()"), "deactivation armed once the panels are shown")
        #expect(text.contains("overlayGuard?.stop()"), "disarmed when the session ends")
        #expect(text.contains("self?.finish(.cancelled)"), "a closing reason is a cancel, never a capture")
        #expect(text.contains("kVK_Escape"), "the key monitors still handle Escape")
        // A kill switch closes the chooser through the service, not by waiting for the timeout.
        let service = try String(contentsOf: PortSourceScrubTests.portKit
            .appendingPathComponent("Services/QuickTools/ScreenCaptureService.swift"), encoding: .utf8)
        #expect(service.contains("func cancelActiveSelection()") && service.contains("var hasActiveSession: Bool"))
    }
}
