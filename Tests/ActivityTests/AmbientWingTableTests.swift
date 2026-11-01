import Foundation
import IslandUI
import Testing
@testable import IslandKit

/// The fixed wing table, the clock slot, the "no bare icon" rule and Claude at rest. All pure.
@Suite struct AmbientWingTableTests {
    private let all = ClosedIslandSettings(enabled: Set(AmbientChannel.userChoices))

    private func make(_ channel: String, text: String? = "1", priority: ActivityPriority = .ambient,
                      urgent: Bool = false, id: String? = nil) -> AmbientIndicator {
        AmbientIndicator(id: id ?? channel, channel: channel, symbol: "circle", text: text, priority: priority, isUrgent: urgent)
    }

    private func ids(_ items: [AmbientIndicator]) -> [String] { items.map(\.id) }

    private let clock = AmbientReadings.clock(Date(timeIntervalSince1970: 1_800_000_000), locale: Locale(identifier: "fr_FR"),
                                              timeZone: TimeZone(identifier: "UTC")!, hours: .h24)

    // MARK: Table

    @Test func channelsLiveOnTheirFixedWing() {
        for channel in [AmbientChannel.claude, AmbientChannel.limits, AmbientChannel.music, AmbientChannel.network] {
            #expect(AmbientWingTable.wing(for: channel) == .leading, "\(channel)")
        }
        for channel in [AmbientChannel.battery, AmbientChannel.system, AmbientChannel.keepAwake, AmbientChannel.mic,
                        AmbientChannel.camera, AmbientChannel.disk, AmbientChannel.volume] {
            #expect(AmbientWingTable.wing(for: channel) == .trailing, "\(channel)")
        }
        #expect(AmbientWingTable.wing(for: AmbientChannel.clock) == nil)
        #expect(AmbientWingTable.wing(for: AmbientChannel.alert) == nil)
    }

    @Test func theTableBeatsAnIndicatorsOwnPreference() {
        var battery = make(AmbientChannel.battery)
        battery.wing = .leading  // an old poster's preference
        let out = ClosedIslandLayout.resolve([battery], settings: all, centered: true)
        #expect(ids(out.trailing) == ["battery"] && out.leading.isEmpty)
    }

    @Test func defaultOrderInsideAWingFollowsTheTable() {
        let input = [make(AmbientChannel.network), make(AmbientChannel.music), make(AmbientChannel.limits),
                     make(AmbientChannel.disk), make(AmbientChannel.system), make(AmbientChannel.battery)]
        // Two per wing at most: the first page holds the first two of each wing's table order.
        let out = ClosedIslandLayout.resolve(input, settings: all, centered: true)
        #expect(ids(out.leading) == ["limits", "music"])
        #expect(ids(out.trailing) == ["battery", "system"])
        // The next page continues the same order.
        let next = ClosedIslandLayout.resolve(input, settings: all, step: 1, centered: true)
        #expect(ids(next.leading) == ["network"] && ids(next.trailing) == ["disk"])
    }

    @Test func batteryIsOnTheRightEvenWithNoClaude() {
        let out = ClosedIslandLayout.resolve([make(AmbientChannel.battery, text: "82%"), clock], settings: all, centered: true)
        #expect(ids(out.trailing) == ["battery"])
        #expect(out.center?.channel == AmbientChannel.clock)
    }

    // MARK: Centre and notch

    @Test func withoutANotchTheClockIsTheCentreAndNeverInAWing() {
        let out = ClosedIslandLayout.resolve([clock, make(AmbientChannel.battery)], settings: all, centered: true)
        #expect(out.center?.text == clock.text)
        #expect(!out.all.contains { $0.channel == AmbientChannel.clock })
    }

    @Test func withANotchTheClockIsTheInnermostItemOfTheLeftWing() {
        let claude = AmbientIndicator(id: "claude", channel: AmbientChannel.claude, symbol: "sparkles", priority: .claudeWorking,
                                      isBusy: true, clockSince: Date(timeIntervalSince1970: 1))
        let out = ClosedIslandLayout.resolve([clock, claude, make(AmbientChannel.battery)], settings: all, centered: false)
        #expect(out.center == nil)
        #expect(ids(out.leading) == ["claude", "clock"])
        #expect(ids(out.trailing) == ["battery"])
    }

    @Test func theNotchDecisionComesFromTheGeometry() {
        let screen = CGRect(x: 0, y: 0, width: 3440, height: 1440)
        let external = NotchGeometry.idle(screenFrame: screen, safeAreaTop: 0, auxLeft: nil, auxRight: nil)
        #expect(!external.hasNotch)
        let built = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let notched = NotchGeometry.idle(
            screenFrame: built, safeAreaTop: 32, auxLeft: CGRect(x: 0, y: 950, width: 656, height: 32),
            auxRight: CGRect(x: 856, y: 950, width: 656, height: 32))
        #expect(notched.hasNotch)
        // A positive safe area with no auxiliary areas is not a notch we can place wings around.
        #expect(!NotchGeometry.idle(screenFrame: built, safeAreaTop: 32, auxLeft: nil, auxRight: nil).hasNotch)
    }

    // MARK: Pins

    @Test func claudeWaitingPinsLeftAndLowBatteryPinsRight() {
        let waiting = AmbientIndicator(id: "claude", channel: AmbientChannel.claude, symbol: "hand.raised.fill",
                                       priority: .claudeWaiting, isUrgent: true, clockSince: Date(timeIntervalSince1970: 1))
        var low = make(AmbientChannel.battery, text: "14%", priority: .alert, urgent: true)
        low.status = .warning
        let flowing = [make(AmbientChannel.music, priority: .music), make(AmbientChannel.network),
                       make(AmbientChannel.system, id: "cpu"), make(AmbientChannel.disk)]
        for step in 0..<4 {
            let out = ClosedIslandLayout.resolve(flowing + [waiting, low], settings: all, step: step, centered: true)
            #expect(out.leading.first?.id == "claude")
            #expect(out.trailing.first?.id == "battery")
        }
    }

    @Test func anAlertTakesTheSideWithRoom() {
        var alert = make(AmbientChannel.alert, text: "45 s", priority: .alert, urgent: true)
        alert.wing = .leading
        let leftFull = [
            AmbientIndicator(id: "claude", channel: AmbientChannel.claude, symbol: "s", priority: .claudeWorking, isBusy: true,
                             clockSince: Date(timeIntervalSince1970: 1)),
            AmbientIndicator(id: "claude2", channel: AmbientChannel.claude, symbol: "s", priority: .claudeWaiting, isUrgent: true,
                             clockSince: Date(timeIntervalSince1970: 1)),
        ]
        let out = ClosedIslandLayout.resolve(leftFull + [alert], settings: all, centered: true)
        #expect(out.leading.count == 2 && ids(out.trailing) == ["alert"])
    }

    // MARK: Rotation and symmetry

    @Test func moreThanTwoItemsPerWingRotateInPages() {
        let items = [make(AmbientChannel.music, priority: .music), make(AmbientChannel.network), make(AmbientChannel.limits)]
        var seen = Set<String>()
        var pages = 0
        for step in 0..<4 {
            let out = ClosedIslandLayout.resolve(items, settings: all, step: step, centered: true)
            #expect(out.leading.count <= 2)
            pages = out.pageCount
            seen.formUnion(ids(out.leading))
        }
        #expect(pages == 2)
        #expect(seen == ["limits", "music", "network"])
    }

    @Test func oneSidedContentReservesTheSameWidthAsTheOtherSide() {
        let item = AmbientReadings.cpu(load: 0.4)
        let left = ClosedIslandContent(leading: [item], trailing: [], center: clock)
        let right = ClosedIslandContent(leading: [], trailing: [item], center: clock)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(AmbientMetrics.pillExtent(left, now: date) == AmbientMetrics.pillExtent(right, now: date))
    }

    // MARK: No bare icon

    @Test func anIconWithoutAValueIsNeverReadable() {
        let arrow = AmbientIndicator(id: "network.1down", channel: AmbientChannel.network, symbol: "arrow.down", text: nil)
        let chip = AmbientIndicator(id: "system.cpu", channel: AmbientChannel.system, symbol: "cpu", text: "")
        let disk = AmbientIndicator(id: "disk", channel: AmbientChannel.disk, symbol: "internaldrive")
        let speaker = AmbientIndicator(id: "volume", channel: AmbientChannel.volume, symbol: "speaker.wave.2.fill")
        for item in [arrow, chip, disk, speaker] { #expect(!item.isReadable, "\(item.id)") }
        let out = ClosedIslandLayout.resolve([arrow, chip, disk, speaker, clock], settings: all, centered: true)
        #expect(out.all.isEmpty && out.center != nil)
    }

    @Test func statesThatMeanSomethingStayReadable() {
        for item in [AmbientReadings.mic(), AmbientReadings.camera(),
                     AmbientIndicator(id: "keepawake", channel: AmbientChannel.keepAwake, symbol: "cup.and.saucer.fill"),
                     AmbientReadings.network(link: .offline, vpn: false, downBytesPerSecond: 0, upBytesPerSecond: 0)[0]] {
            #expect(item.isReadable, "\(item.id)")
            #expect(!item.accessibilityLabel().isEmpty)
        }
    }

    @Test func fittingDropsTheWholeElementInsteadOfLeavingItsIcon() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let down = AmbientReadings.network(link: .wifi, vpn: false, downBytesPerSecond: 80_000, upBytesPerSecond: 0)
        let cpu = AmbientReadings.cpu(load: 0.4)
        let fitted = AmbientMetrics.fitted(down + [cpu], width: 70, now: date)
        #expect(fitted.allSatisfy { $0.isReadable })
        for item in fitted where item.channel != AmbientChannel.claude { #expect(item.text != nil) }
        let tight = AmbientMetrics.fitted([cpu], width: 30, now: date)
        #expect(tight.isEmpty)
    }

    @Test func aWorkingClaudeKeepsItsGlyphWhenOnlyTheClockIsCut() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let claude = AmbientIndicator(id: "claude", channel: AmbientChannel.claude, symbol: "sparkles", status: .info,
                                      priority: .claudeWorking, isBusy: true, clockSince: date.addingTimeInterval(-30))
        let out = AmbientMetrics.fitted([claude], width: 40, now: date)
        #expect(out.count == 1 && out[0].clockSince == nil)
    }

    @Test func networkShowsNothingWithoutTrafficOrBeforeTheFirstDelta() {
        #expect(AmbientReadings.network(link: .wifi, vpn: false, downBytesPerSecond: 0, upBytesPerSecond: 0).isEmpty)
        #expect(AmbientReadings.network(link: .wifi, vpn: false, downBytesPerSecond: 400, upBytesPerSecond: 999).isEmpty)
        let down = AmbientReadings.network(link: .wifi, vpn: false, downBytesPerSecond: 80_000, upBytesPerSecond: 0)
        #expect(down.map(\.id) == [AmbientReadings.downID])  // only the direction that moves
        let idle = AmbientReadings.network(link: .wifi, vpn: false, downBytesPerSecond: 0, upBytesPerSecond: 0, showIdle: true)
        #expect(idle.map(\.text) == ["0 Ko/s", "0 Ko/s"])
        let vpn = AmbientReadings.network(link: .wifi, vpn: true, downBytesPerSecond: 0, upBytesPerSecond: 0)
        #expect(vpn.map(\.text) == ["VPN"])
    }

    @Test func everyBuilderYieldsAReadableIndicator() {
        let built: [AmbientIndicator] = [
            AmbientReadings.cpu(load: 0.4), AmbientReadings.memory(usedBytes: 9_000_000_000, pressure: .normal),
            AmbientReadings.disk(freeBytes: 100_000_000_000), AmbientReadings.mic(), AmbientReadings.camera(),
            AmbientReadings.volume(level: 0.5, muted: false), AmbientReadings.volume(level: 0, muted: true), clock,
        ] + AmbientReadings.network(link: .wired, vpn: true, downBytesPerSecond: 5_000_000, upBytesPerSecond: 2_000_000)
        for item in built { #expect(item.isReadable, "\(item.id)") }
    }

    // MARK: Claude at rest

    private let hour: TimeInterval = 3600

    @Test func weekRingShowsFromAFreshReading() {
        let reading = ClaudeRestReading.make(weekUsed: 0.62, sessionUsed: nil, showLeft: false, age: 600)
        let item = ClaudeRest.indicator(reading: reading, sessionOpen: false)
        #expect(item?.progress == 0.62 && item?.text == nil && item?.isDimmed == false)
        #expect(item?.channel == AmbientChannel.limits && item?.badge == nil)
    }

    @Test func aStaleWeekReadingIsDimmedNotDropped() {
        let reading = ClaudeRestReading.make(weekUsed: 0.62, sessionUsed: nil, showLeft: false, age: 7 * hour)
        #expect(reading.isDimmed && reading.weekFill == 0.62)
        let fresh = ClaudeRestReading.make(weekUsed: 0.62, sessionUsed: nil, showLeft: false, age: 5 * hour)
        #expect(!fresh.isDimmed)
        let old = ClaudeRestReading.make(weekUsed: 0.62, sessionUsed: nil, showLeft: false, age: 8 * 24 * hour)
        #expect(old.weekFill == nil && !old.hasNumbers)
    }

    @Test func aSessionPercentageShowsOnlyWhenTheCallerHasOne() {
        let both = ClaudeRestReading.make(weekUsed: 0.4, sessionUsed: 0.25, showLeft: true, age: 60)
        #expect(both.weekFill == 0.6 && both.sessionText == "75%")
        let none = ClaudeRestReading.make(weekUsed: 0.4, sessionUsed: nil, showLeft: false, age: 5 * hour)
        #expect(none.sessionText == nil)
    }

    @Test func noDataAndNoSessionDrawsNothing() {
        #expect(ClaudeRest.indicator(reading: nil, sessionOpen: false) == nil)
        let pending = ClaudeRestReading.make(weekUsed: nil, sessionUsed: nil, showLeft: false, age: nil)
        #expect(ClaudeRest.indicator(reading: pending, sessionOpen: false) == nil)
    }

    @Test func pendingWithAnOpenSessionIsTheGlyphAloneWithItsStateDot() {
        let pending = ClaudeRestReading.make(weekUsed: nil, sessionUsed: nil, showLeft: false, age: nil)
        let item = ClaudeRest.indicator(reading: pending, sessionOpen: true)
        #expect(item?.text == nil && item?.progress == nil && item?.badge == .success)
        #expect(item?.isReadable == true)
        #expect(item?.channel == AmbientChannel.claude)
        #expect(item?.accessibilityLabel().contains("session ouverte") == true)
    }

    @Test func restIndicatorSurvivesTheLayoutOnTheLeft() {
        let reading = ClaudeRestReading.make(weekUsed: 0.3, sessionUsed: 0.1, showLeft: false, age: 60)
        let item = ClaudeRest.indicator(reading: reading, sessionOpen: true)!
        let out = ClosedIslandLayout.resolve([item, AmbientReadings.cpu(load: 0.2), clock], settings: all, centered: true)
        #expect(out.leading.first?.id == ClaudeRest.id)
        #expect(out.trailing.first?.channel == AmbientChannel.system)
    }

    @Test func dangerStatusFollowsTheWorstWindow() {
        #expect(ClaudeRestReading.make(weekUsed: 0.5, sessionUsed: 0.95, showLeft: true, age: 1).status == .danger)
        #expect(ClaudeRestReading.make(weekUsed: 0.8, sessionUsed: nil, showLeft: false, age: 1).status == .warning)
    }
}

@Suite struct AmbientKeepAwakeCupTests {
    private let all = ClosedIslandSettings(enabled: Set(AmbientChannel.userChoices))
    private let battery = AmbientIndicator(id: "battery", channel: AmbientChannel.battery, symbol: "battery.75percent", text: "32%")
    private let cpu = AmbientReadings.cpu(load: 0.3)

    @Test func theCupIsOnTheRightWingRightAfterTheBattery() {
        let cup = AmbientReadings.keepAwake(active: true, always: false)!
        let out = ClosedIslandLayout.resolve([cpu, cup, battery], settings: all, centered: true)
        #expect(out.trailing.map(\.id) == ["battery", "keepawake"])
        // The system indicators come after it, on the next page.
        let next = ClosedIslandLayout.resolve([cpu, cup, battery], settings: all, step: 1, centered: true)
        #expect(next.trailing.map(\.id) == ["system.cpu"])
    }

    @Test func theCupIsOnTheRightWingOfANotchedScreenToo() {
        let cup = AmbientReadings.keepAwake(active: true, always: false)!
        let out = ClosedIslandLayout.resolve([battery, cup], settings: all, centered: false)
        #expect(out.trailing.map(\.id) == ["battery", "keepawake"] && out.leading.isEmpty)
    }

    @Test func activeShowsTheCupInTheAccentColourWithItsLabel() {
        let cup = AmbientReadings.keepAwake(active: true, always: false)
        #expect(cup?.status == .info && cup?.isDimmed == false)
        #expect(cup?.label == "Garder éveillé actif")
        #expect(cup?.accessibilityLabel().contains("Garder éveillé actif") == true)
    }

    @Test func inactiveHidesTheCupUnlessTheUserAsksForIt() {
        #expect(AmbientReadings.keepAwake(active: false, always: false) == nil)
        let dimmed = AmbientReadings.keepAwake(active: false, always: true)
        #expect(dimmed?.isDimmed == true && dimmed?.status == .neutral)
        #expect(dimmed?.label == "Garder éveillé inactif")
    }

    @Test func aStatusGlyphWithALabelSurvivesTheNoBareIconRule() {
        for cup in [AmbientReadings.keepAwake(active: true, always: false)!, AmbientReadings.keepAwake(active: false, always: true)!] {
            #expect(cup.text == nil && cup.isReadable)
            let out = ClosedIslandLayout.resolve([cup], settings: all, centered: true)
            #expect(out.trailing.map(\.id) == ["keepawake"])
        }
        // And a tight wing keeps it: it has no text to lose.
        let cup = AmbientReadings.keepAwake(active: true, always: false)!
        #expect(AmbientMetrics.fitted([cup], width: 40, now: Date()).count == 1)
    }

    @Test func theAlwaysOptionIsOffByDefaultAndPersists() {
        #expect(ClosedIslandSettings.standard.keepAwakeAlways == false)
        #expect(ClosedIslandKeys.keepAwakeAlways == "notchIdleKeepAwakeAlways")
        let name = "cup-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(ClosedIslandSettings.read(from: defaults).keepAwakeAlways == false)
        var settings = ClosedIslandSettings.standard
        settings.keepAwakeAlways = true
        settings.write(to: defaults)
        #expect(ClosedIslandSettings.read(from: defaults).keepAwakeAlways)
        #expect(defaults.bool(forKey: "notchIdleKeepAwakeAlways"))
    }

    @Test func switchingTheKeepAwakeChannelOffHidesTheCup() {
        var off = all
        off.enabled.remove(AmbientChannel.keepAwake)
        let cup = AmbientReadings.keepAwake(active: true, always: true)!
        #expect(ClosedIslandLayout.resolve([cup, battery], settings: off, centered: true).trailing.map(\.id) == ["battery"])
    }
}

@MainActor
@Suite struct AmbientCupCenterTests {
    private func rig(always: Bool) -> (center: AmbientCenter, cleanup: () -> Void) {
        let name = "cupc-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        var settings = ClosedIslandSettings.standard
        settings.keepAwakeAlways = always
        settings.write(to: defaults)
        defaults.set(true, forKey: ClosedIslandKeys.migrated)
        let center = AmbientCenter(activity: ActivityCenter(), preferences: ClosedIslandPreferences(defaults: defaults), isNotched: false,
                                   sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
        return (center, { defaults.removePersistentDomain(forName: name) })
    }

    @Test func theCupFollowsKeepAwakeAndTheAlwaysOption() {
        let off = rig(always: false); defer { off.cleanup() }
        #expect(off.center.content.trailing.isEmpty)
        off.center.setKeepAwake(active: true)
        #expect(off.center.content.trailing.map(\.id) == ["keepawake"])
        #expect(off.center.content.trailing.first?.isDimmed == false)
        off.center.setKeepAwake(active: false)
        #expect(off.center.content.trailing.isEmpty)

        let always = rig(always: true); defer { always.cleanup() }
        #expect(always.center.content.trailing.map(\.id) == ["keepawake"])
        #expect(always.center.content.trailing.first?.isDimmed == true)
        always.center.setKeepAwake(active: true)
        #expect(always.center.content.trailing.first?.isDimmed == false)
    }
}

@MainActor
@Suite struct AmbientRestCenterTests {
    private func center(notched: Bool) -> AmbientCenter {
        let name = "rest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        ClosedIslandSettings.standard.write(to: defaults)
        defaults.set(true, forKey: ClosedIslandKeys.migrated)
        return AmbientCenter(activity: ActivityCenter(), preferences: ClosedIslandPreferences(defaults: defaults), isNotched: notched,
                             sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
    }

    @Test func theCenterDrawsClaudeAtRestAndYieldsToAWorkingSession() {
        let center = center(notched: false)
        center.setClaudeRest(ClaudeRestReading.make(weekUsed: 0.3, sessionUsed: nil, showLeft: false, age: 60))
        #expect(center.content.leading.first?.id == ClaudeRest.id)
        center.setClaude(ClaudeWorkSample(id: "s", isWaiting: false, since: Date()))
        center.post(AmbientIndicator(id: "claude", channel: AmbientChannel.claude, symbol: "sparkles", priority: .claudeWorking,
                                     isBusy: true, clockSince: Date()))
        #expect(center.content.leading.map(\.id) == ["claude"])
        center.withdraw(id: "claude")
        #expect(center.content.leading.first?.id == ClaudeRest.id)
    }

    @Test func anOpenSessionAloneGivesTheGlyphWithItsDot() {
        let center = center(notched: false)
        #expect(center.content.leading.isEmpty)
        center.setClaudeSessionOpen(true)
        #expect(center.content.leading.first?.badge == .success)
        center.setClaudeSessionOpen(false)
        #expect(center.content.leading.isEmpty)
    }
}
