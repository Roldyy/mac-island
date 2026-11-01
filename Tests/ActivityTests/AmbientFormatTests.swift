import Foundation
import IslandUI
import Testing
@testable import IslandKit

@Suite struct AmbientFormatTests {
    private let utc = TimeZone(identifier: "UTC")!
    private let french = Locale(identifier: "fr_FR")
    private let american = Locale(identifier: "en_US")

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: Throughput

    @Test func ratesUseFrenchUnitsAndThreeSignificantDigits() {
        #expect(AmbientFormat.rate(0) == "0 Ko/s")
        #expect(AmbientFormat.rate(80_000) == "80 Ko/s")
        #expect(AmbientFormat.rate(1_234_000) == "1,23 Mo/s")
        #expect(AmbientFormat.rate(1_200_000) == "1,2 Mo/s")
        #expect(AmbientFormat.rate(12_340_000) == "12,3 Mo/s")
        #expect(AmbientFormat.rate(123_400_000) == "123 Mo/s")
        #expect(AmbientFormat.rate(5_000_000_000) == "5 Go/s")
    }

    @Test func belowOneKilobyteIsNoiseAndNonsenseReadsZero() {
        #expect(AmbientFormat.rate(999) == "0 Ko/s")
        #expect(AmbientFormat.rate(-5_000) == "0 Ko/s")
        #expect(AmbientFormat.rate(.nan) == "0 Ko/s")
        #expect(AmbientFormat.rate(.infinity) == "0 Ko/s")
    }

    @Test func aValueJustBelowTheNextUnitRollsOverInsteadOfPrintingFourDigits() {
        #expect(AmbientFormat.rate(999_600) == "1 Mo/s")
        #expect(AmbientFormat.rate(99_960) == "100 Ko/s")
    }

    @Test func aRateOnlyChangesWhenItsThreeDigitsDo() {
        #expect(AmbientFormat.rate(1_231_000) == AmbientFormat.rate(1_234_000))
        #expect(AmbientFormat.rate(1_234_000) != AmbientFormat.rate(1_300_000))
    }

    // MARK: Percent

    @Test func percentRoundsToFive() {
        #expect(AmbientFormat.percent(0.31) == "30%")
        #expect(AmbientFormat.percent(0.32) == "30%")
        #expect(AmbientFormat.percent(0.33) == "35%")
        #expect(AmbientFormat.percent(0.97) == "95%")
        #expect(AmbientFormat.percent(0.98) == "100%")
        #expect(AmbientFormat.percent(0) == "0%")
    }

    @Test func percentIsClampedAndFinite() {
        #expect(AmbientFormat.roundedPercent(1.7) == 100)
        #expect(AmbientFormat.roundedPercent(-0.4) == 0)
        #expect(AmbientFormat.roundedPercent(.nan) == 0)
        #expect(AmbientFormat.roundedPercent(0.123, step: 1) == 12)
    }

    @Test func aWobblingLoadDoesNotChangeTheShownPercent() {
        let shown = Set([0.301, 0.31, 0.315, 0.322, 0.324].map { AmbientFormat.roundedPercent($0) })
        #expect(shown == [30])
    }

    // MARK: Sizes

    @Test func gigabytesAreDecimalAndShort() {
        #expect(AmbientFormat.gigabytes(9_200_000_000) == "9,2 Go")
        #expect(AmbientFormat.gigabytes(12_340_000_000) == "12 Go")
        #expect(AmbientFormat.gigabytes(128_000_000_000) == "128 Go")
        #expect(AmbientFormat.gigabytes(1_200_000_000_000) == "1,2 To")
        #expect(AmbientFormat.gigabytes(0) == "0,0 Go")
    }

    // MARK: Time and date

    @Test func theTimeFollowsTheLocaleHourCycle() {
        let noon = date(2026, 11, 1, 14, 32)
        #expect(AmbientFormat.time(noon, locale: french, timeZone: utc) == "14:32")
        let us = AmbientFormat.time(noon, locale: american, timeZone: utc)
        #expect(us.contains("2:32") && us.contains("PM"))
    }

    @Test func theHourCycleCanBeForced() {
        let noon = date(2026, 11, 1, 14, 32)
        #expect(AmbientFormat.time(noon, locale: american, timeZone: utc, hours: .h24) == "14:32")
        let forced = AmbientFormat.time(noon, locale: french, timeZone: utc, hours: .h12)
        #expect(forced.contains("2:32") && forced.contains("PM"))
    }

    @Test func theTimeUsesTheTimeZone() {
        let moment = date(2026, 11, 1, 23, 30)
        let paris = TimeZone(identifier: "Europe/Paris")!
        #expect(AmbientFormat.time(moment, locale: french, timeZone: paris) == "00:30")
    }

    @Test func theShortDateIsWeekdayDayMonthWithoutTheTrailingPeriod() {
        #expect(AmbientFormat.shortDate(date(2026, 11, 1, 12, 0), timeZone: utc) == "dim. 1 nov")
        #expect(AmbientFormat.shortDate(date(2026, 11, 7, 12, 0), timeZone: utc) == "sam. 7 nov")
        #expect(!AmbientFormat.shortDate(date(2026, 3, 4, 12, 0), timeZone: utc).hasSuffix("."))
    }

    @Test func theClockWakesOnTheMinuteBoundary() {
        let minute = Date(timeIntervalSince1970: 1_800_000_000 - 1_800_000_000.truncatingRemainder(dividingBy: 60))
        #expect(AmbientFormat.secondsToNextMinute(from: minute) == 60)
        #expect(abs(AmbientFormat.secondsToNextMinute(from: minute.addingTimeInterval(30)) - 30) < 0.001)
        #expect(abs(AmbientFormat.secondsToNextMinute(from: minute.addingTimeInterval(59.5)) - 0.5) < 0.001)
    }

    // MARK: Strings fit their slot (no marquee, nothing under 11 pt needed)

    @Test func theWorstCaseStringsStayWithinTheTextSlot() {
        let worst = ["999 Mo/s", "99,9 Mo/s", "999 Ko/s", "100%", "999 Go", "12,3 To", "VPN", "Muet", "100%"]
        for text in worst {
            #expect(AmbientMetrics.textWidth(text) <= AmbientMetrics.maxTextWidth, "\(text) would scroll")
        }
    }
}
