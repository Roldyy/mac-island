import Foundation
import IslandUI
import Testing
@testable import IslandKit

/// Draws the closed island in each state, on a dark and a mid-gray desktop, to PNG files under
/// `$TMPDIR/mac-island-closed`. The assertions only check that a picture came out; the pictures are for eyes.
@MainActor
@Suite struct AmbientRenderTests {
    private enum Sample {
        static let limits = AmbientIndicator(
            id: "limits", channel: AmbientChannel.limits, symbol: "sparkle", text: "58%", progress: 0.58, wing: .leading)
        static let limitsHigh = AmbientIndicator(
            id: "limits", channel: AmbientChannel.limits, symbol: "sparkle", text: "92%", status: .danger, progress: 0.92, wing: .leading)
        static let battery = AmbientIndicator(
            id: "battery", channel: AmbientChannel.battery, symbol: "battery.75percent", text: "82%", wing: .trailing)
        static let charging = AmbientIndicator(
            id: "battery", channel: AmbientChannel.battery, symbol: "battery.100percent.bolt", text: "64%", status: .success, wing: .trailing)
        static let lowBattery = AmbientIndicator(
            id: "battery", channel: AmbientChannel.battery, symbol: "battery.25percent", text: "14%", status: .warning,
            priority: .alert, isUrgent: true, wing: .trailing)
        static let keepAwake = AmbientIndicator(
            id: "keepawake", channel: AmbientChannel.keepAwake, symbol: "cup.and.saucer.fill", status: .info, wing: .trailing)
        static let music = AmbientIndicator(
            id: "music", channel: AmbientChannel.music, symbol: "waveform", text: "Hollow Years - Dream Theater",
            progress: 0.4, priority: .music, wing: .trailing, glyph: .equalizer)
        static let since = AmbientRender.clock.addingTimeInterval(-453)
        static let working = AmbientIndicator(
            id: "claude", channel: AmbientChannel.claude, symbol: "sparkles", status: .info,
            priority: .claudeWorking, wing: .leading, isBusy: true, clockSince: since)
        static let waiting = AmbientIndicator(
            id: "claude", channel: AmbientChannel.claude, symbol: "hand.raised.fill", status: .warning,
            priority: .claudeWaiting, isUrgent: true, wing: .leading, clockSince: since)
    }

    private func shoot(_ name: String, _ indicators: [AmbientIndicator], settings: ClosedIslandSettings = .standard,
                       step: Int = 0, pulse: Double? = nil) {
        for notched in [false, true] {
            for dark in [true, false] {
                let center = AmbientRender.center(notched: notched, settings: settings, step: step, indicators: indicators)
                let tag = "\(name)-\(notched ? "notch" : "pill")-\(dark ? "dark" : "gray")"
                let url = AmbientRender.png(center: center, notched: notched, dark: dark, name: tag, pulse: pulse)
                #expect(url != nil, "\(tag) did not render")
            }
        }
    }

    @Test func idleNothing() { shoot("01-idle-none", []) }
    @Test func idleLimitsAndBattery() { shoot("02-idle-limits-battery", [Sample.limits, Sample.battery]) }
    @Test func claudeWorking() { shoot("03-claude-working", [Sample.working, Sample.limits, Sample.battery]) }
    @Test func claudeWaitingPulse() { shoot("04-claude-waiting", [Sample.waiting, Sample.battery], pulse: 0.35) }
    @Test func musicPlaying() { shoot("05-music", [Sample.limits, Sample.music]) }
    @Test func charging() { shoot("06-charging", [Sample.charging, Sample.limits]) }
    @Test func lowBattery() { shoot("07-low-battery", [Sample.lowBattery, Sample.limitsHigh], pulse: 0.35) }
    @Test func keepAwakeOn() { shoot("08-keepawake", [Sample.keepAwake, Sample.limits]) }
    @Test func twoPerWing() { shoot("09-two-per-wing", [Sample.working, Sample.limits, Sample.battery, Sample.keepAwake]) }
    @Test func rotatingStepTwo() {
        shoot("10-rotating-step2", [Sample.limits, Sample.battery, Sample.keepAwake, Sample.music], step: 1)
    }
    @Test func oneAndTwoPerWingSettings() {
        shoot("11-one-per-wing", [Sample.limits, Sample.battery, Sample.keepAwake],
              settings: ClosedIslandSettings(maxPerWing: 1))
    }
}
