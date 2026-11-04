import Foundation
import IslandKit
import Testing
@testable import ShellKit

/// Thresholds, French text and the readings the built-in chips build, with no system call.
@MainActor
@Suite struct StatusChipLevelsTests {
    // MARK: Levels

    @Test func cpuIsAttentionFromSeventyFiveAndAlertFromNinety() {
        #expect(StatusChipLevels.cpu(0.0) == .normal)
        #expect(StatusChipLevels.cpu(0.70) == .normal)
        #expect(StatusChipLevels.cpu(0.75) == .attention)
        #expect(StatusChipLevels.cpu(0.87) == .attention)
        // Judged on the value shown (rounded to 5 %), like the pill: 89 % reads 90 %.
        #expect(StatusChipLevels.cpu(0.89) == .alert)
        #expect(StatusChipLevels.cpu(0.90) == .alert)
        #expect(StatusChipLevels.cpu(1.0) == .alert)
        #expect(StatusChipLevels.cpu(0.72) == .normal)
        #expect(StatusChipLevels.cpu(0.73) == .attention)
    }

    @Test func memoryPressureMapsToLevels() {
        #expect(StatusChipLevels.memory(.normal) == .normal)
        #expect(StatusChipLevels.memory(.warning) == .attention)
        #expect(StatusChipLevels.memory(.critical) == .alert)
    }

    @Test func diskIsAttentionUnderTenPercentAndAlertUnderFive() {
        #expect(StatusChipLevels.disk(freeFraction: 0.50) == .normal)
        #expect(StatusChipLevels.disk(freeFraction: 0.10) == .normal)
        #expect(StatusChipLevels.disk(freeFraction: 0.099) == .attention)
        #expect(StatusChipLevels.disk(freeFraction: 0.05) == .attention)
        #expect(StatusChipLevels.disk(freeFraction: 0.049) == .alert)
        #expect(StatusChipLevels.disk(freeFraction: 0) == .alert)
        #expect(StatusChipLevels.disk(freeFraction: .nan) == .normal)
    }

    @Test func levelsAreOrderedAndMapToStatuses() {
        #expect(StatusChipReading.Level.normal < .attention && StatusChipReading.Level.attention < .alert)
        #expect(StatusChipReading.Level.normal.status == .neutral)
        #expect(StatusChipReading.Level.attention.status == .warning)
        #expect(StatusChipReading.Level.alert.status == .danger)
    }

    // MARK: French text

    @Test func percentUsesAFrenchSpaceAndTheStep() {
        #expect(StatusChipLevels.percent(0.234) == "25 %")
        #expect(StatusChipLevels.percent(0.234, step: 1) == "23 %")
        #expect(StatusChipLevels.percent(1.7, step: 1) == "100 %")
        #expect(StatusChipLevels.percent(-1, step: 1) == "0 %")
    }

    @Test func temperatureAndRatesAreFrench() {
        #expect(StatusChipLevels.temperature(62.4) == "62 °C")
        #expect(StatusChipLevels.temperature(.nan) == "—")
        #expect(StatusChipLevels.rates(down: 1_234_567, up: 80_000) == "↓ 1,23 Mo/s  ↑ 80 Ko/s")
        #expect(StatusChipLevels.rates(down: 0, up: 500) == "↓ 0 Ko/s  ↑ 0 Ko/s")
    }

    // MARK: Network reading

    @Test func theNetworkChipNamesTheLinkWithoutAnSSID() {
        func reading(_ link: NetworkLink, vpn: Bool = false, down: Double? = 2_000_000, up: Double? = 50_000) -> StatusChipReading {
            NetworkChipSource.reading(.init(link: link, vpn: vpn, down: down, up: up))
        }
        #expect(reading(.wifi).primary == "Wi-Fi" && reading(.wifi).symbol == "wifi")
        #expect(reading(.wired).primary == "Ethernet")
        #expect(reading(.other).primary == "Réseau")
        #expect(reading(.wifi).secondary == "↓ 2 Mo/s  ↑ 50 Ko/s")
        #expect(reading(.wifi, vpn: true).secondary == "VPN · ↓ 2 Mo/s  ↑ 50 Ko/s")
        #expect(reading(.wifi).level == .normal)
    }

    @Test func offlineIsAnAlertWithNoRates() {
        let offline = NetworkChipSource.reading(.init(link: .offline, vpn: false, down: 10_000, up: 10_000))
        #expect(offline.primary == "Hors ligne" && offline.symbol == "wifi.slash")
        #expect(offline.level == .alert && offline.secondary == nil)
        #expect(NetworkChipSource.reading(.init(link: .offline, vpn: true, down: nil, up: nil)).secondary == "VPN")
    }

    @Test func ratesWaitForASecondSample() {
        let first = NetworkChipSource.reading(.init(link: .wifi, vpn: false, down: nil, up: nil))
        #expect(first.primary == "Wi-Fi" && first.secondary == nil)
    }

    // MARK: Load reading

    @Test func theLoadChipShowsCpuThenRamThenTemperature() throws {
        let reading = try #require(LoadChipSource.reading(.init(cpu: 0.5, memory: 0.614, pressure: .normal), temperature: 62.4))
        #expect(reading.primary == "CPU 50 %")
        #expect(reading.secondary == "RAM 61 % · 62 °C")
        #expect(reading.level == .normal)
        let cool = try #require(LoadChipSource.reading(.init(cpu: 0.5, memory: 0.614, pressure: .normal), temperature: nil))
        #expect(cool.secondary == "RAM 61 %")
    }

    @Test func theLoadLevelIsTheWorstOfCpuAndMemoryPressure() throws {
        func level(_ cpu: Double?, _ pressure: MemoryPressure) throws -> StatusChipReading.Level {
            try #require(LoadChipSource.reading(.init(cpu: cpu, memory: 0.4, pressure: pressure), temperature: nil)).level
        }
        #expect(try level(0.30, .normal) == .normal)
        #expect(try level(0.80, .normal) == .attention)
        #expect(try level(0.95, .normal) == .alert)
        #expect(try level(0.30, .warning) == .attention)
        #expect(try level(0.80, .critical) == .alert)
        #expect(try level(nil, .critical) == .alert)
    }

    @Test func theLoadChipFallsBackToRamAndHidesWithNothing() throws {
        let ramOnly = try #require(LoadChipSource.reading(.init(cpu: nil, memory: 0.5, pressure: .normal), temperature: nil))
        #expect(ramOnly.primary == "RAM 50 %" && ramOnly.secondary == nil)
        #expect(LoadChipSource.reading(.init(cpu: nil, memory: nil, pressure: .normal), temperature: 60) == nil)
    }

    // MARK: Disk reading

    @Test func theDiskChipShowsFreeSpaceAndItsLevel() {
        let roomy = DiskChipSource.reading(.init(free: 412_000_000_000, total: 1_000_000_000_000))
        #expect(roomy.primary == "412 Go" && roomy.secondary == "libres" && roomy.level == .normal)
        #expect(DiskChipSource.reading(.init(free: 80_000_000_000, total: 1_000_000_000_000)).level == .attention)
        #expect(DiskChipSource.reading(.init(free: 40_000_000_000, total: 1_000_000_000_000)).level == .alert)
        #expect(DiskChipSource.reading(.init(free: 9_200_000_000, total: 0)).level == .normal)
    }

    // MARK: Reading value

    @Test func progressIsClampedAndOnlyFinite() {
        #expect(StatusChipReading(kind: .timer, primary: "1:00", progress: 1.4).progress == 1)
        #expect(StatusChipReading(kind: .timer, primary: "1:00", progress: -2).progress == 0)
        #expect(StatusChipReading(kind: .timer, primary: "1:00", progress: .nan).progress == nil)
        #expect(StatusChipReading(kind: .timer, primary: "1:00").progress == nil)
    }

    @Test func aReadingDefaultsToItsKindSymbolAndSpeaksItsLevel() {
        let reading = StatusChipReading(kind: .disk, primary: "9 Go", secondary: "libres", level: .alert)
        #expect(reading.symbol == "internaldrive" && reading.id == .disk)
        #expect(reading.accessibilityText == "Disque : 9 Go, libres. Alerte")
        #expect(StatusChipReading(kind: .network, primary: "Wi-Fi").accessibilityText == "Réseau : Wi-Fi")
    }

    @Test func equalityIgnoresTheHandlerButNotTheTitle() {
        let a = StatusChipReading(kind: .network, primary: "Wi-Fi", actions: [StatusChipAction(title: "Ouvrir") {}])
        let b = StatusChipReading(kind: .network, primary: "Wi-Fi", actions: [StatusChipAction(title: "Ouvrir") { _ = 1 }])
        let c = StatusChipReading(kind: .network, primary: "Wi-Fi", actions: [StatusChipAction(title: "Fermer") {}])
        #expect(a == b)
        #expect(a != c)
    }
}
