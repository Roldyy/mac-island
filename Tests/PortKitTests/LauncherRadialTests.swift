import Foundation
import Testing
@testable import PortKit

/// Lane W5-D, the radial menu and what the user configured on it: the pure geometry, the close rules of the overlay,
/// the tap policy against a fake tap, and the launch of apps, files and links through a fake workspace.
@Suite struct LauncherRadialTests {
    // MARK: Geometry (pure)

    @Test func theAngleRunsClockwiseFromTwelveOClock() {
        func angle(_ dx: CGFloat, _ dyUp: CGFloat) -> CGFloat { RadialMenuGeometry.angle(dx: dx, dyUp: dyUp) }
        #expect(angle(0, 1) == 0)
        #expect(abs(angle(1, 0) - .pi / 2) < 1e-9)
        #expect(abs(angle(0, -1) - .pi) < 1e-9)
        #expect(abs(angle(-1, 0) - 3 * .pi / 2) < 1e-9)
        for (dx, dyUp) in [(0.3, 0.9), (-0.7, 0.2), (-0.1, -0.9), (0.9, -0.3)] {
            let value = angle(CGFloat(dx), CGFloat(dyUp))
            #expect(value >= 0 && value < 2 * .pi)
        }
    }

    @Test func everySliceCenterHitsItsOwnIndexForEveryWheelSize() {
        for count in 1...12 {
            for index in 0..<count {
                let unit = RadialMenuGeometry.unitPosition(index: index, itemCount: count)
                let hit = RadialMenuGeometry.highlightedIndex(dx: unit.dx * 100, dyUp: unit.dyUp * 100,
                                                              deadZoneRadius: RadialMenuLayout.deadZoneRadius,
                                                              itemCount: count)
                #expect(hit == index, "\(index) of \(count)")
            }
        }
        // Slice 0 sits at 12 o'clock, the next ones clockwise.
        let top = RadialMenuGeometry.unitPosition(index: 0, itemCount: 4)
        let right = RadialMenuGeometry.unitPosition(index: 1, itemCount: 4)
        #expect(abs(top.dx) < 1e-9 && abs(top.dyUp - 1) < 1e-9)
        #expect(abs(right.dx - 1) < 1e-9 && abs(right.dyUp) < 1e-9)
    }

    @Test func theHubIsADeadZoneAndAnEmptyWheelHighlightsNothing() {
        let dead = RadialMenuLayout.deadZoneRadius
        #expect(RadialMenuGeometry.highlightedIndex(dx: 0, dyUp: 0, deadZoneRadius: dead, itemCount: 6) == nil)
        #expect(RadialMenuGeometry.highlightedIndex(dx: 0, dyUp: dead - 0.5, deadZoneRadius: dead, itemCount: 6) == nil)
        #expect(RadialMenuGeometry.highlightedIndex(dx: 0, dyUp: dead, deadZoneRadius: dead, itemCount: 6) == 0)
        #expect(RadialMenuGeometry.highlightedIndex(dx: 50, dyUp: 50, deadZoneRadius: dead, itemCount: 0) == nil)
        #expect(RadialMenuGeometry.index(forAngle: 1, itemCount: 0) == nil)
    }

    @Test func sliceBoundariesSplitHalfwayBetweenTwoCenters() {
        // Six slices of 60 degrees: slice 0 spans -30 to +30 degrees.
        let step = 2 * CGFloat.pi / 6
        #expect(RadialMenuGeometry.index(forAngle: step / 2 - 0.001, itemCount: 6) == 0)
        #expect(RadialMenuGeometry.index(forAngle: step / 2 + 0.001, itemCount: 6) == 1)
        #expect(RadialMenuGeometry.index(forAngle: 2 * .pi - 0.001, itemCount: 6) == 0, "just left of 12 o'clock wraps to 0")
    }

    @Test func theLayoutKeepsTheChipsInsideTheWheelAndTheWheelInsideThePanel() {
        #expect(RadialMenuLayout.ringRadius + RadialMenuLayout.chipSize / 2 <= RadialMenuLayout.wheelDiameter / 2)
        #expect(RadialMenuLayout.wheelDiameter < RadialMenuLayout.panelSize)
        #expect(RadialMenuLayout.hubDiameter / 2 < RadialMenuLayout.deadZoneRadius + 0.001)
        #expect(RadialMenuLayout.deadZoneRadius < RadialMenuLayout.ringRadius - RadialMenuLayout.chipSize / 2 + 30)
    }

    // MARK: Overlay close rules

    @Test func theWheelClosesWhenAnotherAppBecomesFrontmostButNotForItsOwnWindows() {
        #expect(RadialOverlayRules.closesOnActivation(activated: "com.apple.finder", own: "be.roldy.macisland"))
        #expect(!RadialOverlayRules.closesOnActivation(activated: "be.roldy.macisland", own: "be.roldy.macisland"))
        #expect(RadialOverlayRules.closesOnActivation(activated: nil, own: "be.roldy.macisland"), "an app with no id counts")
    }

    @Test func releasingTheHeldButtonEndsTheHoldPhaseAndNothingElseDoes() {
        #expect(RadialOverlayRules.releaseEndsHold(holdPhase: true, heldButton: 3, released: 3))
        #expect(!RadialOverlayRules.releaseEndsHold(holdPhase: true, heldButton: 3, released: 4), "another button")
        #expect(!RadialOverlayRules.releaseEndsHold(holdPhase: false, heldButton: 3, released: 3), "already sticky")
        #expect(!RadialOverlayRules.releaseEndsHold(holdPhase: true, heldButton: nil, released: 3), "a chord session")
    }

    @Test func escapeLeavesASubmenuFirstThenTheWheel() {
        #expect(RadialOverlayRules.escapeAction(depth: 1) == .close)
        #expect(RadialOverlayRules.escapeAction(depth: 2) == .stepBack)
        #expect(RadialOverlayRules.escapeAction(depth: 3) == .stepBack)
        #expect(RadialOverlayRules.escapeAction(depth: 0) == .close)
    }

    /// Time by hand: a clock and a scheduler that only move when the test says so.
    final class ManualTime {
        var now: TimeInterval = 100
        private struct Item { let fireAt: TimeInterval; let work: () -> Void; var cancelled = false }
        private var items: [Item] = []

        var schedule: RadialIdleWatchdog.Schedule {
            { [self] delay, work in
                let index = items.count
                items.append(Item(fireAt: now + delay, work: work))
                return { [self] in items[index].cancelled = true }
            }
        }

        var clock: () -> TimeInterval { { [self] in now } }

        func advance(by seconds: TimeInterval) {
            let target = now + seconds
            while let next = items.indices.filter({ !items[$0].cancelled && items[$0].fireAt <= target })
                .min(by: { items[$0].fireAt < items[$1].fireAt }) {
                now = max(now, items[next].fireAt)
                items[next].cancelled = true
                items[next].work()
            }
            now = target
        }
    }

    func watchdog(_ time: ManualTime) -> RadialIdleWatchdog {
        RadialIdleWatchdog(timeout: 3, schedule: time.schedule, now: time.clock)
    }

    @Test func anIdleWheelClosesAfterThreeSeconds() {
        #expect(RadialOverlayRules.idleTimeout == 3)
        let time = ManualTime()
        let dog = watchdog(time)
        var closed = 0
        dog.arm { closed += 1 }
        #expect(dog.isArmed)
        time.advance(by: 2.9)
        #expect(closed == 0)
        time.advance(by: 0.2)
        #expect(closed == 1)
        #expect(!dog.isArmed, "one expiry, then it is spent")
        time.advance(by: 30)
        #expect(closed == 1)
    }

    @Test func activityPushesTheDeadlineBackAndOnlyIdleTimeCounts() {
        let time = ManualTime()
        let dog = watchdog(time)
        var closed = 0
        dog.arm { closed += 1 }
        time.advance(by: 2)
        dog.touch()  // a pointer move at t = 2
        time.advance(by: 2)  // t = 4: only 2 s since the move
        #expect(closed == 0)
        dog.touch()
        time.advance(by: 2.9)
        #expect(closed == 0)
        time.advance(by: 0.2)
        #expect(closed == 1, "3 s after the LAST activity")
    }

    @Test func disarmingCancelsTheCloseAndReArmingStartsAFreshCountdown() {
        let time = ManualTime()
        let dog = watchdog(time)
        var closed = 0
        dog.arm { closed += 1 }
        time.advance(by: 1)
        dog.disarm()
        #expect(!dog.isArmed)
        time.advance(by: 10)
        #expect(closed == 0, "the wheel was closed by other means")
        dog.touch()  // not armed: a no-op
        dog.arm { closed += 10 }
        time.advance(by: 2.9)
        #expect(closed == 0)
        time.advance(by: 0.2)
        #expect(closed == 10)
        // Arming twice keeps one countdown, the second callback.
        dog.arm { closed += 100 }
        dog.arm { closed += 1000 }
        time.advance(by: 4)
        #expect(closed == 1010)
    }

    // MARK: Tap policy against a fake tap

    /// A stand-in for the CGEventTap: created, enabled, torn down. The policy decides, this applies.
    struct FakeTap {
        var held = false
        var enabled = false
        var creations = 0
        var teardowns = 0

        mutating func sync(wanted: Bool, accessibility: Bool, session: Bool) {
            switch RadialTapPolicy.decide(tapHeld: held, tapEnabled: enabled, featureWanted: wanted,
                                          accessibilityGranted: accessibility, sessionIsActive: session) {
            case .teardown:
                if held { teardowns += 1 }
                held = false
                enabled = false
            case .keep:
                break
            case .rebuild:
                teardowns += 1
                creations += 1
                held = true
                enabled = true
            case .create:
                creations += 1
                held = true
                enabled = true
            }
        }
    }

    @Test func theTapIsCreatedOnlyWhenWantedGrantedAndOnScreen() {
        for (wanted, accessibility, session) in [(false, true, true), (true, false, true), (true, true, false),
                                                 (false, false, false)] {
            var tap = FakeTap()
            tap.sync(wanted: wanted, accessibility: accessibility, session: session)
            #expect(!tap.held && tap.creations == 0, "wanted \(wanted) ax \(accessibility) session \(session)")
        }
        var tap = FakeTap()
        tap.sync(wanted: true, accessibility: true, session: true)
        #expect(tap.held && tap.enabled && tap.creations == 1)
    }

    @Test func aSecondSyncKeepsAHealthyTapAndNeverStacksAnother() {
        var tap = FakeTap()
        for _ in 0..<5 { tap.sync(wanted: true, accessibility: true, session: true) }
        #expect(tap.creations == 1 && tap.teardowns == 0)
    }

    @Test func aTapTheSystemDisabledIsRebuiltNotKept() {
        var tap = FakeTap()
        tap.sync(wanted: true, accessibility: true, session: true)
        tap.enabled = false  // the system switched it off (Accessibility revoked then regranted)
        tap.sync(wanted: true, accessibility: true, session: true)
        #expect(tap.held && tap.enabled && tap.creations == 2 && tap.teardowns == 1, "re-armed")
    }

    @Test func stopRevokeAndASwitchedAwaySessionAllRemoveTheTap() {
        func armed() -> FakeTap {
            var tap = FakeTap()
            tap.sync(wanted: true, accessibility: true, session: true)
            return tap
        }
        var stopped = armed()
        stopped.sync(wanted: false, accessibility: true, session: true)  // the feature stopped
        #expect(!stopped.held && stopped.teardowns == 1)
        var revoked = armed()
        revoked.sync(wanted: true, accessibility: false, session: true)
        #expect(!revoked.held && revoked.teardowns == 1)
        var switchedAway = armed()
        switchedAway.sync(wanted: true, accessibility: true, session: false)
        #expect(!switchedAway.held, "a tap left behind would stall the account on screen")
        switchedAway.sync(wanted: true, accessibility: true, session: true)
        #expect(switchedAway.held, "and it comes back with the session")
    }

    @Test func theServiceRoutesItsSyncAndItsReleaseThroughTheRulesAndTheWatchdog() throws {
        let path = "Services/RadialMenu/RadialMenuService.swift"
        let lines = try #require(PortSourceScrubTests.files.first { $0.path == path }).lines
            .filter { !$0.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("//") }
        let text = lines.joined(separator: "\n")
        #expect(text.contains("RadialTapPolicy.decide("))
        #expect(text.contains("RadialOverlayRules.releaseEndsHold("))
        #expect(text.contains("RadialOverlayRules.closesOnActivation("))
        #expect(text.contains("idle.arm") && text.contains("idle.disarm()"), "armed with the monitors, disarmed with them")
        #expect(text.components(separatedBy: "idle.touch()").count - 1 >= 4, "pointer, key, modifiers and selection")
        // Upstream's own contract, kept: a claimed button never hands half a click back.
        let claimed = text.components(separatedBy: "if type == .otherMouseDown {").dropFirst().first?
            .components(separatedBy: "private func hotkeyPressed").first ?? ""
        #expect(!claimed.isEmpty && !claimed.contains("passUnretained"))
    }

    // MARK: Launching what the user configured

    final class FakeWorkspace: RadialWorkspace {
        var events: [String] = []
        var existing: Set<String> = []
        var failApplications = false

        func openApplication(at url: URL, onFailure: @escaping () -> Void) {
            events.append("app:\(url.path)")
            if failApplications { onFailure() }
        }

        func open(_ url: URL) { events.append("open:\(url.absoluteString)") }

        func fileExists(atPath path: String) -> Bool { existing.contains(path) }
    }

    func item(_ kind: RadialMenuItem.Kind, _ payload: String) -> RadialMenuItem {
        RadialMenuItem(kind: kind, name: "x", payload: payload)
    }

    @Test func anAppOpensThroughOpenApplicationWithTheTildeExpanded() {
        let workspace = FakeWorkspace()
        var beeps = 0
        let outcome = RadialItemLauncher.launch(item(.app, "~/Applications/Notes.app"), workspace: workspace) { beeps += 1 }
        #expect(outcome == .launched)
        #expect(workspace.events == ["app:\(NSHomeDirectory())/Applications/Notes.app"])
        #expect(beeps == 0)
        workspace.failApplications = true
        _ = RadialItemLauncher.launch(item(.app, "/Applications/Gone.app"), workspace: workspace) { beeps += 1 }
        #expect(beeps == 1, "a launch the system refuses beeps")
    }

    @Test func aFileOpensOnlyWhenItExistsAndABrokenOneBeepsInstead() {
        let workspace = FakeWorkspace()
        workspace.existing = ["/Users/me/report.pdf"]
        var beeps = 0
        #expect(RadialItemLauncher.launch(item(.file, "/Users/me/report.pdf"), workspace: workspace) { beeps += 1 } == .launched)
        #expect(workspace.events == ["open:file:///Users/me/report.pdf"])
        #expect(RadialItemLauncher.launch(item(.file, "/Users/me/gone.pdf"), workspace: workspace) { beeps += 1 } == .missingFile)
        #expect(workspace.events.count == 1 && beeps == 1)
    }

    @Test func aLinkIsNormalizedAndOpenedAndAnInvalidOneIsIgnored() {
        let workspace = FakeWorkspace()
        var beeps = 0
        #expect(RadialItemLauncher.launch(item(.url, "example.com/page"), workspace: workspace) { beeps += 1 } == .launched)
        #expect(RadialItemLauncher.launch(item(.url, "https://roldy.be"), workspace: workspace) { beeps += 1 } == .launched)
        #expect(workspace.events == ["open:https://example.com/page", "open:https://roldy.be"])
        #expect(RadialItemLauncher.launch(item(.url, "not a link"), workspace: workspace) { beeps += 1 } == .ignored)
        #expect(RadialItemLauncher.launch(item(.url, ""), workspace: workspace) { beeps += 1 } == .ignored)
        #expect(workspace.events.count == 2 && beeps == 0)
    }

    @Test func everyOtherKindOpensNothing() {
        let workspace = FakeWorkspace()
        var beeps = 0
        for kind in RadialMenuItem.Kind.allCases where ![.app, .file, .url].contains(kind) {
            #expect(RadialItemLauncher.launch(item(kind, "anything"), workspace: workspace) { beeps += 1 } == .ignored, "\(kind)")
        }
        #expect(workspace.events.isEmpty && beeps == 0)
    }

    @Test func aPathWithShellCharactersIsStillOnlyDataForTheWorkspace() {
        let workspace = FakeWorkspace()
        workspace.existing = ["/tmp/a; rm -rf ~"]
        _ = RadialItemLauncher.launch(item(.file, "/tmp/a; rm -rf ~"), workspace: workspace) {}
        #expect(workspace.events.count == 1, "one fixed call with the whole string as a path")
        #expect(workspace.events[0] == "open:file:///tmp/a%3B%20rm%20-rf%20~", "percent-encoded into a file URL: \(workspace.events[0])")
    }
}
