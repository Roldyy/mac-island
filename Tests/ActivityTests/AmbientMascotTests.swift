import Foundation
import IslandTestSupport
import IslandUI
import Testing
@testable import IslandKit

/// The companion in the closed island: an opt-in indicator in a wing, pinned, counted in the width, absent by default.
@MainActor
@Suite struct AmbientMascotTests {
    private func mascot(_ wing: AmbientWing = .leading) -> AmbientIndicator {
        AmbientIndicator(id: "mascot", channel: AmbientChannel.mascot, symbol: "face.smiling", wing: wing, glyph: .mascot,
                         label: "Compagnon")
    }

    private let clock = AmbientIndicator(id: "clock", channel: AmbientChannel.clock, symbol: "", text: "12:34", glyph: .none)
    private let battery = AmbientIndicator(id: "battery", channel: AmbientChannel.battery, symbol: "battery.75percent",
                                           text: "82%", wing: .trailing)
    private let cup = AmbientIndicator(id: "keepawake", channel: AmbientChannel.keepAwake, symbol: "cup.and.saucer.fill",
                                       status: .info, wing: .trailing)
    private let rest = AmbientIndicator(id: "claude.rest", channel: AmbientChannel.limits, symbol: "sparkle", text: "58%",
                                        progress: 0.58, wing: .leading)

    private func channels(_ items: [AmbientIndicator]) -> [String] { items.map(\.channel) }

    // MARK: Pure

    @Test func theCompanionIsReadableWithNoTextAndIsNotAUserChannel() {
        #expect(mascot().isReadable)
        #expect(mascot().isPinned)
        #expect(!AmbientChannel.userChoices.contains(AmbientChannel.mascot))
        #expect(ClosedIslandSettings.standard.isEnabled(AmbientChannel.mascot), "its feature switch is the opt-in")
        #expect(!AmbientChannel.defaultOn.contains(AmbientChannel.mascot))
    }

    @Test func absentByDefaultTheClosedIslandKeepsHaroldsFiveIndicators() {
        for notched in [true, false] {
            let out = ClosedIslandLayout.resolve([rest, battery, cup, clock], settings: .standard, centered: !notched)
            #expect(!(out.all + [out.center].compactMap { $0 }).contains { $0.channel == AmbientChannel.mascot })
        }
    }

    @Test func presentOnItsSideAndNeverRotatedAway() {
        for side in [AmbientWing.leading, .trailing] {
            let input = [mascot(side), rest, battery, cup, clock]
            for step in 0..<6 {
                let out = ClosedIslandLayout.resolve(input, settings: .standard, step: step, centered: false)
                let wing = side == .leading ? out.leading : out.trailing
                #expect(channels(wing).contains(AmbientChannel.mascot), "step \(step), \(side)")
            }
        }
    }

    @Test func onAScreenWithoutANotchTheCompanionSitsBesideTheCenterClock() {
        let out = ClosedIslandLayout.resolve([mascot(.leading), clock], settings: .standard, centered: true)
        #expect(channels(out.leading) == [AmbientChannel.mascot])
        #expect(out.center?.channel == AmbientChannel.clock)
    }

    // MARK: Width

    @Test func theCompanionCountsInTheWingWidthMath() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(AmbientMetrics.elementWidth(mascot(), now: now) == AmbientMetrics.glyphSize)
        let alone = AmbientMetrics.groupWidth([clock], now: now)
        let with = AmbientMetrics.groupWidth([mascot(), clock], now: now)
        #expect(with == alone + AmbientMetrics.glyphSize + AmbientMetrics.elementGap)
        // And it moves the island's own wing: a wing of only the companion asks for room.
        let content = ClosedIslandContent(leading: [mascot(), rest], trailing: [])
        let bare = ClosedIslandContent(leading: [rest], trailing: [])
        #expect(AmbientMetrics.notchedExtents(content, now: now).leading
                >= AmbientMetrics.notchedExtents(bare, now: now).leading)
        #expect(AmbientMetrics.groupWidth(content.leading, now: now) > AmbientMetrics.groupWidth(bare.leading, now: now))
    }

    @Test func aTightWingShortensTheReadingBeforeItDropsTheCompanion() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        // The right wing at its widest (3 + 76 pt): the battery with its percentage and the companion do not both fit.
        let width = NotchGeometry.baseWing + NotchGeometry.maxWingExtent
        let fitted = AmbientMetrics.fitted([mascot(.trailing), battery], width: width, now: now)
        #expect(channels(fitted) == [AmbientChannel.mascot, AmbientChannel.battery])
        #expect(fitted.last?.text == nil, "the percentage goes first: the battery outline still says the level")
    }

    @Test func aWingTooNarrowForBothKeepsTheReadingElementAndDropsTheCompanion() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fitted = AmbientMetrics.fitted([mascot(.trailing), battery], width: 40, now: now)
        #expect(channels(fitted) == [AmbientChannel.battery])
    }

    // MARK: The center: switch on -> content the closed strip draws

    private func center(notched: Bool, defaults: UserDefaults) -> AmbientCenter {
        ClosedIslandSettings.standard.write(to: defaults)
        defaults.set(true, forKey: ClosedIslandKeys.migrated)
        return AmbientCenter(activity: ActivityCenter(), preferences: ClosedIslandPreferences(defaults: defaults),
                             isNotched: notched, sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
    }

    @Test func postedItShowsInTheStripContentAndWithdrawnItGoes() {
        for notched in [true, false] {
            let bench = TestDefaults.make()
            defer { bench.cleanup() }
            let ambient = center(notched: notched, defaults: bench.defaults)
            ambient.post(clock)
            #expect(!ambient.content.all.contains { $0.channel == AmbientChannel.mascot })
            ambient.post(mascot())
            #expect(ambient.content.all.contains { $0.channel == AmbientChannel.mascot && $0.glyph == .mascot },
                    "notched \(notched)")
            ambient.withdraw(id: "mascot")
            #expect(!ambient.content.all.contains { $0.channel == AmbientChannel.mascot })
        }
    }
}
