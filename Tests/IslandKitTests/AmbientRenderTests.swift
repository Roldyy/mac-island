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

    /// The new indicators, built by the same pure builders the samplers use.
    private enum Reading {
        static let clock = AmbientReadings.clock(
            AmbientRender.clock, locale: Locale(identifier: "fr_FR"), timeZone: TimeZone(identifier: "UTC")!, hours: .h24)
        static let cpu = AmbientReadings.cpu(load: 0.35)
        static let cpuHigh = AmbientReadings.cpu(load: 0.92)
        static let memory = AmbientReadings.memory(usedBytes: 9_200_000_000, pressure: .normal)
        static let memoryWarn = AmbientReadings.memory(usedBytes: 14_800_000_000, pressure: .warning)
        static let network = AmbientReadings.network(link: .wifi, vpn: false, downBytesPerSecond: 1_234_000, upBytesPerSecond: 80_000)
        static let vpn = AmbientReadings.network(link: .wifi, vpn: true, downBytesPerSecond: 12_340_000, upBytesPerSecond: 640_000)
        static let wired = AmbientReadings.network(link: .wired, vpn: false, downBytesPerSecond: 123_000_000, upBytesPerSecond: 4_500_000)
        static let disk = AmbientReadings.disk(freeBytes: 128_000_000_000)
        static let mic = AmbientReadings.mic()
        static let camera = AmbientReadings.camera()
        static let volume = AmbientReadings.volume(level: 0.62, muted: false)
    }

    /// Every channel on, so the opt-in ones (mic, camera, volume, disk) show up in the pictures.
    private let everything = ClosedIslandSettings(enabled: Set(AmbientChannel.userChoices))

    private func leading(_ item: AmbientIndicator) -> AmbientIndicator {
        var copy = item
        copy.wing = .leading
        return copy
    }

    private func trailing(_ item: AmbientIndicator) -> AmbientIndicator {
        var copy = item
        copy.wing = .trailing
        return copy
    }

    private func shoot(_ name: String, _ indicators: [AmbientIndicator], settings: ClosedIslandSettings = .standard,
                       step: Int = 0, pulse: Double? = nil, withClock: Bool = true) {
        let indicators = withClock ? indicators + [Reading.clock] : indicators
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
    // MARK: Clock in the center (no notch) or first in the left wing (notch), and the new indicators

    @Test func clockOnly() { shoot("12-clock-only", []) }
    @Test func clockAndCPU() { shoot("13-clock-cpu", [Reading.cpu, Reading.memory]) }
    @Test func clockWithOneOnTheLeft() { shoot("14-clock-one-left", [leading(Sample.limits)]) }
    @Test func clockWithTwoLeftAndTwoRight() {
        shoot("15-clock-two-left-two-right",
              [leading(Sample.limits), leading(Reading.cpu), trailing(Sample.battery), trailing(Reading.memory)])
    }
    @Test func clockWithAnUrgentAlert() {
        shoot("16-clock-urgent-alert", [Sample.waiting, Sample.battery, Reading.cpu], pulse: 0.35)
    }
    @Test func networkActive() { shoot("17-network", Reading.network + [Reading.cpu], settings: everything) }
    @Test func networkWired() { shoot("18-network-wired", Reading.wired, settings: everything) }
    @Test func vpnActive() { shoot("19-vpn", Reading.vpn, settings: everything) }
    @Test func micInUse() { shoot("20-mic", [Reading.mic, Reading.cpu], settings: everything) }
    @Test func cameraInUse() { shoot("21-camera", [Reading.camera, Reading.mic], settings: everything) }
    @Test func volumeHUD() { shoot("22-volume-hud", [Reading.volume, Reading.cpu, Sample.battery], settings: everything) }
    @Test func lowBatteryPinnedOverRotation() {
        shoot("23-low-battery-pinned", [Sample.lowBattery, Reading.cpu, Reading.memoryWarn, Sample.keepAwake] + Reading.network + [Reading.disk],
              settings: everything, step: 1, pulse: 0.35)
    }
    @Test func twoPerWingPageTwo() {
        shoot("24-two-per-wing-page-2", [Sample.limits, Sample.battery, Reading.cpu, Reading.memory, Reading.disk, Sample.keepAwake] + Reading.network,
              settings: everything, step: 1)
    }
    @Test func twoPerWingPageThree() {
        shoot("25-two-per-wing-page-3", [Sample.limits, Sample.battery, Reading.cpuHigh, Reading.memoryWarn, Reading.disk, Sample.keepAwake] + Reading.network,
              settings: everything, step: 2)
    }
    @Test func clockOffFallsBackToTheOldCenteredRow() {
        var settings = ClosedIslandSettings.standard
        settings.enabled.remove(AmbientChannel.clock)
        shoot("26-clock-off", [Sample.limits, Sample.battery], settings: settings)
    }

    @Test func oneAndTwoPerWingSettings() {
        shoot("11-one-per-wing", [Sample.limits, Sample.battery, Sample.keepAwake],
              settings: ClosedIslandSettings(maxPerWing: 1))
    }
}
