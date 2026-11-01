import CoreGraphics
import Foundation
import IslandUI
import Testing
@testable import IslandKit

/// The closed island hugs the hardware notch: as tall as the notch, as wide as the notch plus two short wings
/// each sized to its content. Measured through the real pipeline (center, layout, metrics, width proxy,
/// `NotchGeometry.closedFrame`), with the default settings, against the 14-inch (180 pt) and 16-inch (200 pt) notch.
/// The same scenes are drawn to `$TMPDIR/mac-island-closed/compact-*.png` in an invisible, far-off window.
@MainActor
@Suite struct AmbientCompactSizeTests {
    private let notches: [CGFloat] = [180, 200]
    private let height = AmbientRender.notchHeight

    private let clock = AmbientReadings.clock(
        AmbientRender.clock, locale: Locale(identifier: "fr_FR"), timeZone: TimeZone(identifier: "UTC")!, hours: .h24)
    private let battery = AmbientIndicator(
        id: "battery", channel: AmbientChannel.battery, symbol: "battery.75percent", text: "82%", wing: .trailing)
    private let lowBattery = AmbientIndicator(
        id: "battery", channel: AmbientChannel.battery, symbol: "battery.25percent", text: "14%", status: .warning,
        priority: .alert, isUrgent: true, wing: .trailing)
    private let since = AmbientRender.clock.addingTimeInterval(-453)
    private let rest = ClaudeRestReading.make(weekUsed: 0.42, sessionUsed: 0.31, showLeft: false, age: 600)

    private enum Scene: CaseIterable {
        case idle, claudeAtRest, claudeWorking, claudeWaiting, lowBattery, cupActive

        var name: String {
            switch self {
            case .idle: "idle"
            case .claudeAtRest: "claude-rest"
            case .claudeWorking: "claude-working"
            case .claudeWaiting: "claude-waiting"
            case .lowBattery: "low-battery"
            case .cupActive: "cup-active"
            }
        }
    }

    private func center(_ scene: Scene, notched: Bool) -> AmbientCenter {
        let working = AmbientIndicator(
            id: "claude", channel: AmbientChannel.claude, symbol: "sparkles", status: .info, priority: .claudeWorking,
            wing: .leading, isBusy: true, clockSince: since)
        let waiting = AmbientIndicator(
            id: "claude", channel: AmbientChannel.claude, symbol: "hand.raised.fill", status: .warning,
            priority: .claudeWaiting, isUrgent: true, wing: .leading, clockSince: since)
        let center: AmbientCenter
        switch scene {
        case .idle:
            center = AmbientRender.center(notched: notched, indicators: [battery, clock])
        case .claudeAtRest:
            center = AmbientRender.center(notched: notched, indicators: [battery, clock])
            center.setClaudeRest(rest)
            center.setClaudeSessionOpen(true)
            center.setKeepAwake(active: true)
        case .claudeWorking:
            center = AmbientRender.center(
                notched: notched, indicators: [working, battery, clock], claude: ClaudeWorkSample(id: "s", isWaiting: false, since: since))
            center.setKeepAwake(active: true)
        case .claudeWaiting:
            center = AmbientRender.center(
                notched: notched, indicators: [waiting, battery, clock], claude: ClaudeWorkSample(id: "s", isWaiting: true, since: since))
        case .lowBattery:
            center = AmbientRender.center(notched: notched, indicators: [lowBattery, clock])
            center.setClaudeRest(rest)
        case .cupActive:
            center = AmbientRender.center(notched: notched, indicators: [battery, clock])
            center.setKeepAwake(active: true)
        }
        return center
    }

    private func size(_ scene: Scene, notch: CGFloat) -> CGSize {
        AmbientRender.closedSize(center: center(scene, notched: true), notched: true, notchWidth: notch, notchHeight: height)
    }

    // MARK: Constants

    @Test func theWingsAreShortAndNothingIsReservedBeyondTheContent() {
        #expect(NotchGeometry.maxWingExtent == 64)
        #expect(NotchGeometry.baseWing <= 3)  // a rim, not a minimum width
        #expect(AmbientMetrics.glyphSize == 14)
        #expect(AmbientMetrics.elementGap == 4)
        #expect(AmbientMetrics.wingPadding >= 3 && AmbientMetrics.wingPadding <= 8)
    }

    // MARK: Heights and widths against the real notch

    @Test func theClosedIslandIsExactlyAsTallAsTheNotch() {
        for notch in notches {
            for scene in Scene.allCases {
                #expect(size(scene, notch: notch).height == height, "\(scene.name) at \(notch)")
            }
        }
    }

    @Test func idleWithOnlyTheClockAndTheBatteryIsTheSmallest() {
        for notch in notches {
            let idle = size(.idle, notch: notch)
            // A short wing each side, no more than the 4-item case needs.
            #expect(idle.width > notch)
            #expect(idle.width <= notch + 2 * 56, "idle \(idle.width) at \(notch)")
            for scene in [Scene.claudeAtRest, .claudeWorking, .claudeWaiting] {
                #expect(idle.width <= size(scene, notch: notch).width, "\(scene.name) is not narrower than idle at \(notch)")
            }
            print("compact-size idle notch \(notch): \(idle.width) x \(idle.height)")
        }
    }

    @Test func theFourDefaultItemsStayNearTheNotchPlusTwoShortWings() {
        for notch in notches {
            let four = size(.claudeAtRest, notch: notch)
            print("compact-size four items notch \(notch): \(four.width) x \(four.height)")
            #expect(four.width <= notch + 2 * 63, "\(four.width) at \(notch)")
            #expect(four.width >= notch + 2 * 40)
        }
    }

    @Test func noSceneGoesBeyondTheLongestWing() {
        for notch in notches {
            for scene in Scene.allCases {
                #expect(size(scene, notch: notch).width <= notch + 2 * NotchGeometry.maxWingExtent, "\(scene.name) at \(notch)")
            }
        }
    }

    @Test func eachWingIsSizedToItsContentAndTheTextOfTheOthersLeavesBeforeTheClock() {
        // Claude (ring + percent) and the clock on the left do not fit one 64 pt wing together: the percent
        // goes, the clock keeps its digits.
        let c = center(.claudeAtRest, notched: true)
        #expect(c.content.leading.contains { $0.channel == AmbientChannel.clock && $0.text != nil })
        #expect(c.content.leading.contains { $0.channel != AmbientChannel.clock && $0.text == nil })
        for item in c.content.leading + c.content.trailing { #expect(item.isReadable) }
    }

    @Test func noMinimumWidthIsAddedToTheWing() {
        let c = center(.idle, notched: true)
        let content = c.content
        let need = max(AmbientMetrics.groupWidth(content.leading, now: AmbientRender.clock),
                       AmbientMetrics.groupWidth(content.trailing, now: AmbientRender.clock))
        let extent = AmbientMetrics.notchedExtent(content, now: AmbientRender.clock)
        #expect(extent == (need + 2 * AmbientMetrics.wingPadding - NotchGeometry.baseWing).rounded(.up))
    }

    @Test func theMeasuredWidthIsTheWidthTheStripIsDrawnAt() {
        // The width proxy asks for exactly `extent` points on each side.
        let c = center(.claudeAtRest, notched: true)
        let extent = AmbientMetrics.notchedExtent(c.content, now: AmbientRender.clock)
        let proxy = NotchGeometry.wingExtent(for: c.widthProxy.layout)
        #expect(proxy == extent)
        #expect(size(.claudeAtRest, notch: 180).width == 180 + 2 * (NotchGeometry.baseWing + extent))
    }

    @Test func aNoNotchPillStaysCompactToo() {
        for scene in Scene.allCases {
            let c = center(scene, notched: false)
            let size = AmbientRender.closedSize(center: c, notched: false)
            #expect(size.height == NotchGeometry.pillHeight)
            #expect(size.width <= NotchGeometry.pillWidth + 2 * NotchGeometry.maxWingExtent, "\(scene.name)")
        }
    }

    // MARK: Pictures (for eyes)

    @Test func rendersTheClosedIslandInEachState() {
        for notch in notches {
            for scene in Scene.allCases {
                for dark in [true, false] {
                    let tag = "compact-\(scene.name)-notch\(Int(notch))-\(dark ? "dark" : "gray")"
                    let url = AmbientRender.png(
                        center: center(scene, notched: true), notched: true, dark: dark, name: tag,
                        pulse: scene == .claudeWaiting || scene == .lowBattery ? 0.35 : nil, notchWidth: notch)
                    #expect(url != nil, "\(tag)")
                }
            }
        }
        for scene in Scene.allCases {
            for dark in [true, false] {
                let tag = "compact-\(scene.name)-pill-\(dark ? "dark" : "gray")"
                #expect(AmbientRender.png(center: center(scene, notched: false), notched: false, dark: dark, name: tag,
                                          pulse: scene == .claudeWaiting || scene == .lowBattery ? 0.35 : nil) != nil, "\(tag)")
            }
        }
    }
}
