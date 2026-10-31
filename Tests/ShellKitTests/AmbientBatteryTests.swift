import Foundation
import IslandKit
import IslandTestSupport
import IslandUI
import Testing
@testable import ShellKit

@Suite struct AmbientBatteryTests {
    private func reading(_ percent: Int, plugged: Bool = false, charging: Bool = false, minutes: Int? = nil) -> BatteryReading {
        BatteryReading(percent: percent, isPluggedIn: plugged, isCharging: charging, minutes: minutes)
    }

    // MARK: Formatting

    @Test func textIsTheCompactPercent() {
        #expect(reading(82).text == "82%")
        #expect(reading(5).text == "5%")
        #expect(reading(100, plugged: true).text == "100%")
    }

    @Test func thePercentIsClampedAndTheEstimateDropsNonsense() {
        #expect(reading(140).percent == 100)
        #expect(reading(-4).percent == 0)
        #expect(reading(50, minutes: -1).minutes == nil)  // IOKit's "still computing"
        #expect(reading(50, minutes: 0).minutes == nil)
        #expect(reading(50, minutes: 95).minutes == 95)
    }

    @Test func theSymbolFollowsTheLevelAndTheChargerGetsTheBolt() {
        #expect(reading(100).symbol == "battery.100percent")
        #expect(reading(87).symbol == "battery.75percent")
        #expect(reading(60).symbol == "battery.50percent")
        #expect(reading(30).symbol == "battery.25percent")
        #expect(reading(9).symbol == "battery.0percent")
        #expect(reading(9, plugged: true, charging: true).symbol == "battery.100percent.bolt")
        #expect(reading(100, plugged: true).symbol == "battery.100percent.bolt")
    }

    @Test func theStatusEscalatesBelowTwentyAndTenAndIsGoodOnTheCharger() {
        #expect(reading(80).status == .neutral)
        #expect(reading(20).status == .neutral)
        #expect(reading(19).status == .warning)
        #expect(reading(9).status == .danger)
        #expect(reading(5, plugged: true, charging: true).status == .success)
    }

    @Test func spokenSentenceCoversLevelChargerAndEstimate() {
        #expect(reading(82).spoken == "Batterie 82 %")
        #expect(reading(64, plugged: true, charging: true, minutes: 75).spoken == "Batterie 64 %, en charge, pleine dans 1 h 15 min")
        #expect(reading(100, plugged: true).spoken == "Batterie 100 %, sur secteur")
        #expect(reading(15, minutes: 25).spoken == "Batterie 15 %, 25 min restantes, niveau bas")
    }

    // MARK: Indicator

    @Test func aHealthyBatteryIsAnAmbientIndicatorOnTheTrailingWing() {
        let i = reading(82).indicator
        #expect(i.id == "battery" && i.channel == AmbientChannel.battery)
        #expect(i.priority == .ambient && !i.isUrgent && !i.isPinned)
        #expect(i.wing == .trailing)
        #expect(i.text == "82%")
        #expect(i.label == "Batterie 82 %")
    }

    @Test func aLowBatteryIsUrgentAndPinned() {
        let i = reading(14).indicator
        #expect(i.isUrgent && i.isPinned && i.priority == .alert)
        #expect(i.status == .warning)
        #expect(i.symbol != "")  // symbol and text carry the state, not only the color
        #expect(reading(8).indicator.status == .danger)
    }

    @Test func aLowBatteryOnTheChargerIsNotUrgent() {
        let i = reading(8, plugged: true, charging: true).indicator
        #expect(!i.isUrgent && !i.isPinned)
        #expect(i.status == .success)
    }

    @Test func exactlyTwentyIsNotLow() {
        #expect(!reading(20).isLow)
        #expect(reading(19).isLow)
    }

    // MARK: Source

    @MainActor @Test func theSourcePostsWhatItReadsAndWithdrawsWhenThereIsNoBattery() {
        let (defaults, cleanup) = TestDefaults.make()
        defer { cleanup() }
        let center = AmbientCenter(activity: ActivityCenter(), preferences: ClosedIslandPreferences(defaults: defaults))
        var next: BatteryReading? = reading(82)
        let source = BatterySource(center: center, read: { next })
        source.refresh()
        #expect(center.content.all.first?.text == "82%")
        next = reading(14)
        source.refresh()
        #expect(center.content.all.first?.isUrgent == true)
        next = nil  // a desktop Mac, or the battery was removed
        source.refresh()
        #expect(center.content.isEmpty)
    }

    @MainActor @Test func theSourceReadsOnStartAndStopWithdraws() {
        let (defaults, cleanup) = TestDefaults.make()
        defer { cleanup() }
        let center = AmbientCenter(activity: ActivityCenter(), preferences: ClosedIslandPreferences(defaults: defaults))
        let source = BatterySource(center: center, read: { BatteryReading(percent: 55, isPluggedIn: false, isCharging: false) })
        source.start()
        #expect(center.content.all.first?.text == "55%")
        source.start()  // idempotent
        source.stop()
        #expect(center.content.isEmpty)
    }

    @Test func theLiveReadingIsEitherAbsentOrSane() {
        // Real hardware in, nothing asserted about the value: a desktop Mac has none.
        if let live = BatteryReading.current() {
            #expect((0...100).contains(live.percent))
        }
    }
}
