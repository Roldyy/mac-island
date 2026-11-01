import Foundation
import IslandUI
import Testing
@testable import IslandKit

/// The delta math of the samplers, driven with fake counters: no system call anywhere in here.
@Suite struct AmbientSamplingTests {
    private func reading(_ name: String, up: Bool = true, ipv4: Bool = false, bytes: (UInt64, UInt64)? = nil) -> InterfaceReading {
        InterfaceReading(name: name, isUp: up, hasIPv4: ipv4,
                         counters: bytes.map { InterfaceCounters(bytesIn: $0.0, bytesOut: $0.1) })
    }

    // MARK: Processor

    @Test func cpuLoadIsTheBusyShareOfTheInterval() {
        let load = SamplingMath.cpuLoad(previous: CPUTicks(busy: 100, total: 400), current: CPUTicks(busy: 150, total: 500))
        #expect(load == 0.5)
        #expect(SamplingMath.cpuLoad(previous: CPUTicks(busy: 0, total: 0), current: CPUTicks(busy: 100, total: 100)) == 1)
        #expect(SamplingMath.cpuLoad(previous: CPUTicks(busy: 10, total: 100), current: CPUTicks(busy: 10, total: 200)) == 0)
    }

    @Test func noTimePassedOrCountersGoingBackwardsGiveNoReading() {
        let base = CPUTicks(busy: 100, total: 400)
        #expect(SamplingMath.cpuLoad(previous: base, current: base) == nil)
        #expect(SamplingMath.cpuLoad(previous: base, current: CPUTicks(busy: 90, total: 500)) == nil)
        #expect(SamplingMath.cpuLoad(previous: base, current: CPUTicks(busy: 120, total: 300)) == nil)
    }

    @Test func memoryPressureReadsTheKernelLevel() {
        #expect(MemoryPressure(level: 1) == .normal)
        #expect(MemoryPressure(level: 2) == .warning)
        #expect(MemoryPressure(level: 4) == .critical)
        #expect(MemoryPressure(level: 0) == .normal)
        #expect(MemoryPressure(level: 99) == .normal)
        #expect(MemoryPressure.normal.status == .success)
        #expect(MemoryPressure.warning.status == .warning)
        #expect(MemoryPressure.critical.status == .danger)
    }

    // MARK: Interfaces

    @Test func onlyRealLinksCountTowardsThroughput() {
        for name in ["en0", "en1", "en12"] { #expect(SamplingMath.isPhysical(name), "\(name)") }
        for name in ["lo0", "awdl0", "llw0", "utun3", "bridge0", "gif0", "stf0", "ap1", "anpi0", "en", "ens4"] {
            #expect(!SamplingMath.isPhysical(name), "\(name)")
        }
    }

    @Test func countersKeepUpPhysicalInterfacesWithCountersOnly() {
        let readings = [
            reading("en0", bytes: (10, 20)), reading("en1", up: false, bytes: (5, 5)), reading("lo0", bytes: (99, 99)),
            reading("utun2", ipv4: true, bytes: (7, 7)), reading("awdl0", bytes: (3, 3)), reading("en2", bytes: nil),
        ]
        let out = SamplingMath.counters(from: readings)
        #expect(Array(out.keys) == ["en0"])
        #expect(out["en0"] == InterfaceCounters(bytesIn: 10, bytesOut: 20))
    }

    @Test func aVPNIsATunnelThatIsUpWithAnIPv4Address() {
        #expect(SamplingMath.vpnActive([reading("utun4", ipv4: true)]))
        #expect(!SamplingMath.vpnActive([reading("utun0"), reading("utun1")]))  // the system's IPv6-only tunnels
        #expect(!SamplingMath.vpnActive([reading("utun4", up: false, ipv4: true)]))
        #expect(!SamplingMath.vpnActive([reading("en0", ipv4: true)]))
        #expect(!SamplingMath.vpnActive([]))
    }

    @Test func theDeltaSumsTheInterfacesPresentInBothSamples() {
        let before = ["en0": InterfaceCounters(bytesIn: 1_000, bytesOut: 500), "en1": InterfaceCounters(bytesIn: 10, bytesOut: 10)]
        let after = ["en0": InterfaceCounters(bytesIn: 3_000, bytesOut: 800), "en1": InterfaceCounters(bytesIn: 60, bytesOut: 10),
                     "en5": InterfaceCounters(bytesIn: 9_999, bytesOut: 9_999)]  // appeared between the samples
        let delta = SamplingMath.delta(previous: before, current: after)
        #expect(delta == InterfaceCounters(bytesIn: 2_050, bytesOut: 300))
    }

    @Test func aThirtyTwoBitCounterWrapIsNotAReset() {
        let before = ["en0": InterfaceCounters(bytesIn: 4_294_967_000, bytesOut: 100)]
        let after = ["en0": InterfaceCounters(bytesIn: 500, bytesOut: 150)]
        let delta = SamplingMath.delta(previous: before, current: after)
        #expect(delta.bytesIn == 796)
        #expect(delta.bytesOut == 50)
    }

    @Test func throughputDividesByTheRealElapsedTime() {
        let rate = SamplingMath.throughput(InterfaceCounters(bytesIn: 2_000_000, bytesOut: 100_000), seconds: 2)
        #expect(rate.down == 1_000_000 && rate.up == 50_000)
        #expect(SamplingMath.throughput(InterfaceCounters(bytesIn: 5, bytesOut: 5), seconds: 0).down == 0)
        #expect(SamplingMath.throughput(InterfaceCounters(bytesIn: 5, bytesOut: 5), seconds: -1).up == 0)
    }

    @Test func aFullSecondPassFromFakeCountersGivesTheShownStrings() {
        let first = ["en0": InterfaceCounters(bytesIn: 0, bytesOut: 0)]
        let second = ["en0": InterfaceCounters(bytesIn: 2_460_000, bytesOut: 160_000)]
        let rate = SamplingMath.throughput(SamplingMath.delta(previous: first, current: second), seconds: 2)
        #expect(AmbientFormat.rate(rate.down) == "1,23 Mo/s")
        #expect(AmbientFormat.rate(rate.up) == "80 Ko/s")
    }

    // MARK: Indicators

    @Test func theClockIndicatorCarriesTheTimeAndTheDateAndNoGlyph() {
        let utc = TimeZone(identifier: "UTC")!
        let moment = Date(timeIntervalSince1970: 1_793_534_400)  // 2026-11-01 12:00 UTC
        let clock = AmbientReadings.clock(moment, locale: Locale(identifier: "fr_FR"), timeZone: utc, hours: .h24)
        #expect(clock.id == "clock" && clock.channel == AmbientChannel.clock)
        #expect(clock.text == "12:00")
        #expect(clock.detail == "dim. 1 nov")
        #expect(clock.glyph == .none)
        #expect(!clock.isPinned)
        #expect(clock.accessibilityLabel() == "Heure, 12:00, dim. 1 nov")
    }

    @Test func cpuStatusEscalatesAndTheTextIsRounded() {
        #expect(AmbientReadings.cpu(load: 0.34).text == "35%")
        #expect(AmbientReadings.cpu(load: 0.5).status == .neutral)
        #expect(AmbientReadings.cpu(load: 0.8).status == .warning)
        #expect(AmbientReadings.cpu(load: 0.95).status == .danger)
        #expect(AmbientReadings.cpu(load: 0.5).channel == AmbientChannel.system)
    }

    @Test func memoryIsADotColoredByPressureWithTheUsedGigabytes() {
        let normal = AmbientReadings.memory(usedBytes: 9_200_000_000, pressure: .normal)
        #expect(normal.symbol == "circle.fill" && normal.text == "9,2 Go" && normal.status == .success)
        #expect(AmbientReadings.memory(usedBytes: 9_200_000_000, pressure: .warning).status == .warning)
        #expect(AmbientReadings.memory(usedBytes: 9_200_000_000, pressure: .critical).status == .danger)
        #expect(normal.channel == AmbientChannel.system)
        #expect(normal.accessibilityLabel().contains("pression normale"))
    }

    @Test func diskWarnsWhenSpaceRunsLow() {
        #expect(AmbientReadings.disk(freeBytes: 128_000_000_000).status == .neutral)
        #expect(AmbientReadings.disk(freeBytes: 10_000_000_000).status == .warning)
        #expect(AmbientReadings.disk(freeBytes: 3_000_000_000).status == .danger)
        #expect(AmbientReadings.disk(freeBytes: 128_000_000_000).text == "128 Go")
    }

    @Test func networkShowsDownThenUpAndNoBareConnectionGlyph() {
        let items = AmbientReadings.network(link: .wifi, vpn: false, downBytesPerSecond: 1_234_000, upBytesPerSecond: 80_000)
        #expect(items.map(\.id) == [AmbientReadings.downID, AmbientReadings.upID])
        #expect(items.map(\.symbol) == ["arrow.down", "arrow.up"])
        #expect(items.map(\.text) == ["1,23 Mo/s", "80 Ko/s"])
        #expect(items.allSatisfy { $0.channel == AmbientChannel.network })
    }

    @Test func aVPNTagsTheLinkAndAWiredLinkChangesTheGlyph() {
        let vpn = AmbientReadings.network(link: .wired, vpn: true, downBytesPerSecond: 0, upBytesPerSecond: 0)
        #expect(vpn[0].symbol == "cable.connector.horizontal" && vpn[0].text == "VPN" && vpn[0].status == .info)
        #expect(vpn[0].accessibilityLabel().contains("VPN actif"))
    }

    @Test func offlineShowsTheGlyphAloneAndNoRates() {
        let items = AmbientReadings.network(link: .offline, vpn: false, downBytesPerSecond: 5_000_000, upBytesPerSecond: 5_000_000)
        #expect(items.count == 1)
        #expect(items[0].symbol == "wifi.slash" && items[0].status == .warning)
    }

    @Test func theNetworkSignatureOnlyChangesWithWhatIsShown() {
        let a = AmbientReadings.networkSignature(link: .wifi, vpn: false, down: 1_231_000, up: 80_010)
        let b = AmbientReadings.networkSignature(link: .wifi, vpn: false, down: 1_234_000, up: 80_040)
        #expect(a == b)
        #expect(a != AmbientReadings.networkSignature(link: .wifi, vpn: true, down: 1_234_000, up: 80_400))
        #expect(a != AmbientReadings.networkSignature(link: .wired, vpn: false, down: 1_234_000, up: 80_400))
        #expect(a != AmbientReadings.networkSignature(link: .wifi, vpn: false, down: 2_000_000, up: 80_400))
    }

    @Test func micAndCameraArePinnedButDoNotPulse() {
        let mic = AmbientReadings.mic(), camera = AmbientReadings.camera()
        #expect(mic.isPinned && !mic.isUrgent && mic.status == .warning && mic.symbol == "mic.fill")
        #expect(camera.isPinned && !camera.isUrgent && camera.status == .success && camera.symbol == "video.fill")
        #expect(mic.channel == AmbientChannel.mic && camera.channel == AmbientChannel.camera)
    }

    @Test func theVolumeIsABarAndAPercentPinnedOverTheRotation() {
        let level = AmbientReadings.volume(level: 0.624, muted: false)
        #expect(level.text == "62%" && level.bar == 0.624 && level.isPinned)
        #expect(level.symbol == "speaker.wave.2.fill")
        #expect(AmbientReadings.volume(level: 0.1, muted: false).symbol == "speaker.wave.1.fill")
        #expect(AmbientReadings.volume(level: 0.9, muted: false).symbol == "speaker.wave.3.fill")
        let muted = AmbientReadings.volume(level: 0.5, muted: true)
        #expect(muted.symbol == "speaker.slash.fill" && muted.text == "Muet" && muted.bar == 0)
        #expect(AmbientReadings.volume(level: 3, muted: false).bar == 1)
        #expect(AmbientReadings.volume(level: .nan, muted: false).text == "0%")
    }
}
