import Foundation
import IslandUI
import Testing
@testable import IslandKit

/// The closed island in the states Harold looks at: Claude left, clock center, battery right. PNGs go to
/// `$TMPDIR/mac-island-closed` (names start with `rest-`), drawn in an invisible window far off screen.
@MainActor
@Suite struct AmbientRestRenderTests {
    private let everything = ClosedIslandSettings(enabled: Set(AmbientChannel.userChoices))

    private let clock = AmbientReadings.clock(
        AmbientRender.clock, locale: Locale(identifier: "fr_FR"), timeZone: TimeZone(identifier: "UTC")!, hours: .h24)
    private let battery = AmbientIndicator(
        id: "battery", channel: AmbientChannel.battery, symbol: "battery.75percent", text: "32%", wing: .trailing)
    private let lowBattery = AmbientIndicator(
        id: "battery", channel: AmbientChannel.battery, symbol: "battery.25percent", text: "14%", status: .warning,
        priority: .alert, isUrgent: true, wing: .trailing)
    private let since = AmbientRender.clock.addingTimeInterval(-453)

    private func shoot(_ name: String, indicators: [AmbientIndicator], rest: ClaudeRestReading? = nil, sessionOpen: Bool = false,
                       settings: ClosedIslandSettings? = nil, step: Int = 0, claude: ClaudeWorkSample? = nil,
                       cup: Bool? = nil) {
        for notched in [false, true] {
            for dark in [true, false] {
                let center = AmbientRender.center(
                    notched: notched, settings: settings ?? everything, step: step, indicators: indicators + [clock], claude: claude)
                center.setClaudeRest(rest)
                center.setClaudeSessionOpen(sessionOpen)
                if let cup { center.setKeepAwake(active: cup) }
                let tag = "rest-\(name)-\(notched ? "notch" : "pill")-\(dark ? "dark" : "gray")"
                #expect(AmbientRender.png(center: center, notched: notched, dark: dark, name: tag) != nil, "\(tag)")
            }
        }
    }

    @Test func idleWeekRingClockBattery() {
        let rest = ClaudeRestReading.make(weekUsed: 0.62, sessionUsed: nil, showLeft: false, age: 600)
        shoot("idle", indicators: [battery], rest: rest)
    }

    @Test func idleWithSessionOpenAndSessionPercent() {
        let rest = ClaudeRestReading.make(weekUsed: 0.62, sessionUsed: 0.31, showLeft: false, age: 600)
        shoot("idle-session", indicators: [battery], rest: rest, sessionOpen: true)
    }

    @Test func idleStaleWeekReading() {
        let rest = ClaudeRestReading.make(weekUsed: 0.62, sessionUsed: nil, showLeft: false, age: 9 * 3600)
        shoot("idle-stale", indicators: [battery], rest: rest)
    }

    @Test func pendingGlyphAlone() {
        let rest = ClaudeRestReading.make(weekUsed: nil, sessionUsed: nil, showLeft: false, age: nil)
        shoot("pending-open", indicators: [battery], rest: rest, sessionOpen: true)
        shoot("nodata", indicators: [battery], rest: rest)
    }

    @Test func keepAwakeCupNextToTheBattery() {
        let rest = ClaudeRestReading.make(weekUsed: 0.62, sessionUsed: nil, showLeft: false, age: 600)
        shoot("cup-active", indicators: [battery], rest: rest, cup: true)
        var always = everything
        always.keepAwakeAlways = true
        shoot("cup-dimmed", indicators: [battery], rest: rest, settings: always, cup: false)
    }

    @Test func claudeWorking() {
        let working = AmbientIndicator(
            id: "claude", channel: AmbientChannel.claude, symbol: "sparkles", status: .info, priority: .claudeWorking,
            wing: .leading, isBusy: true, clockSince: since)
        shoot("working", indicators: [working, battery], rest: ClaudeRestReading.make(weekUsed: 0.4, sessionUsed: nil, showLeft: false, age: 60),
              sessionOpen: true, claude: ClaudeWorkSample(id: "s", isWaiting: false, since: since))
    }

    @Test func claudeWaiting() {
        let waiting = AmbientIndicator(
            id: "claude", channel: AmbientChannel.claude, symbol: "hand.raised.fill", status: .warning,
            priority: .claudeWaiting, isUrgent: true, wing: .leading, clockSince: since)
        shoot("waiting", indicators: [waiting, battery], claude: ClaudeWorkSample(id: "s", isWaiting: true, since: since))
    }

    @Test func lowBatteryPinsRight() {
        let rest = ClaudeRestReading.make(weekUsed: 0.9, sessionUsed: nil, showLeft: false, age: 60)
        shoot("lowbattery", indicators: [lowBattery, AmbientReadings.cpu(load: 0.35)], rest: rest)
    }

    @Test func musicAndNetwork() {
        let music = AmbientIndicator(
            id: "music", channel: AmbientChannel.music, symbol: "waveform", text: "Hollow Years", progress: 0.4,
            priority: .music, wing: .trailing, glyph: .equalizer)
        let network = AmbientReadings.network(link: .wifi, vpn: false, downBytesPerSecond: 1_234_000, upBytesPerSecond: 80_000)
        let rest = ClaudeRestReading.make(weekUsed: 0.3, sessionUsed: nil, showLeft: false, age: 60)
        shoot("music-network", indicators: [music, battery] + network, rest: rest)
    }

    @Test func fourItemsPerSideRotate() {
        let music = AmbientIndicator(
            id: "music", channel: AmbientChannel.music, symbol: "waveform", priority: .music, glyph: .equalizer)
        let network = AmbientReadings.network(link: .wifi, vpn: true, downBytesPerSecond: 1_234_000, upBytesPerSecond: 80_000)
        let right: [AmbientIndicator] = [
            battery, AmbientReadings.cpu(load: 0.35), AmbientReadings.disk(freeBytes: 128_000_000_000),
            AmbientReadings.volume(level: 0.6, muted: false),
        ]
        let rest = ClaudeRestReading.make(weekUsed: 0.3, sessionUsed: 0.2, showLeft: false, age: 60)
        for step in 0..<2 {
            shoot("four-step\(step)", indicators: [music] + network + right, rest: rest, step: step)
        }
    }

    /// The bug from the screenshot: no value, no icon. Nothing may render for these.
    @Test func bareIconsRenderNothing() {
        let arrow = AmbientIndicator(id: "network.1down", channel: AmbientChannel.network, symbol: "arrow.down")
        let chip = AmbientIndicator(id: "system.cpu", channel: AmbientChannel.system, symbol: "cpu")
        shoot("bare", indicators: [arrow, chip, battery])
    }
}
