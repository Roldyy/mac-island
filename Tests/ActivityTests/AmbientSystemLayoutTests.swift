import Combine
import Foundation
import IslandUI
import Testing
@testable import IslandKit

/// Ten and more channels: two per wing, pages, the pinned items, the order, the disabled ones, the center clock.
@Suite struct AmbientSystemLayoutTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ id: String, channel: String? = nil, text: String? = "12%", priority: ActivityPriority = .ambient,
                      urgent: Bool = false, wing: AmbientWing? = nil, detail: String? = nil) -> AmbientIndicator {
        AmbientIndicator(id: id, channel: channel ?? id, symbol: "circle", text: text, priority: priority, isUrgent: urgent,
                         wing: wing, detail: detail)
    }

    private func clock(detail: String? = "dim. 1 nov") -> AmbientIndicator {
        AmbientIndicator(id: "clock", channel: AmbientChannel.clock, symbol: "clock", text: "14:32", wing: .leading,
                         glyph: .none, detail: detail)
    }

    private func ids(_ items: [AmbientIndicator]) -> [String] { items.map(\.id) }

    /// Every user channel on, with one indicator per channel (the network has its three).
    private var everything: ClosedIslandSettings {
        ClosedIslandSettings(enabled: Set(AmbientChannel.userChoices))
    }

    private func allIndicators() -> [AmbientIndicator] {
        var out: [AmbientIndicator] = [
            item("limits", channel: AmbientChannel.limits), item("claude", channel: AmbientChannel.claude),
            item("music", channel: AmbientChannel.music), item("battery", channel: AmbientChannel.battery),
            item("keepawake", channel: AmbientChannel.keepAwake),
            item("system.cpu", channel: AmbientChannel.system), item("system.mem", channel: AmbientChannel.system),
            item("disk", channel: AmbientChannel.disk),
        ]
        out += AmbientReadings.networkIDs.map { item($0, channel: AmbientChannel.network) }
        return out
    }

    // MARK: Defaults and keys

    @Test func clockSystemAndNetworkAreOnByDefaultTheOthersOff() {
        let standard = ClosedIslandSettings.standard
        for channel in [AmbientChannel.clock, AmbientChannel.system, AmbientChannel.network,
                        AmbientChannel.limits, AmbientChannel.claude, AmbientChannel.music, AmbientChannel.battery, AmbientChannel.keepAwake] {
            #expect(standard.isEnabled(channel), "\(channel) should be on")
        }
        for channel in [AmbientChannel.disk, AmbientChannel.mic, AmbientChannel.camera, AmbientChannel.volume] {
            #expect(!standard.isEnabled(channel), "\(channel) should be off")
        }
        #expect(standard.isEnabled(AmbientChannel.alert))
    }

    @Test func eachNewChannelHasItsNotchIdleShowKey() {
        #expect(ClosedIslandKeys.show(AmbientChannel.clock) == "notchIdleShowClock")
        #expect(ClosedIslandKeys.show(AmbientChannel.system) == "notchIdleShowSystem")
        #expect(ClosedIslandKeys.show(AmbientChannel.network) == "notchIdleShowNetwork")
        #expect(ClosedIslandKeys.show(AmbientChannel.disk) == "notchIdleShowDisk")
        #expect(ClosedIslandKeys.show(AmbientChannel.mic) == "notchIdleShowMic")
        #expect(ClosedIslandKeys.show(AmbientChannel.camera) == "notchIdleShowCamera")
        #expect(ClosedIslandKeys.show(AmbientChannel.volume) == "notchIdleShowVolume")
        #expect(ClosedIslandKeys.all.contains("notchIdleClockHours"))
        #expect(ClosedIslandKeys.all.allSatisfy { $0.hasPrefix("notchIdle") })
    }

    @Test func theOldKeysKeepTheirNames() {
        #expect(ClosedIslandKeys.show(AmbientChannel.limits) == "notchIdleShowLimits")
        #expect(ClosedIslandKeys.show(AmbientChannel.claude) == "notchIdleShowClaude")
        #expect(ClosedIslandKeys.show(AmbientChannel.music) == "notchIdleShowMusic")
        #expect(ClosedIslandKeys.show(AmbientChannel.battery) == "notchIdleShowBattery")
        #expect(ClosedIslandKeys.show(AmbientChannel.keepAwake) == "notchIdleShowKeepAwake")
    }

    /// A throw-away defaults domain. `migrated` marks the one-time carry-over of `notchIdleContent` as done: a
    /// suite also reads the process-wide registration domain, where other suites of the run may have registered a
    /// legacy value, so a test that is not about the migration must not depend on it.
    private func suite(migrated: Bool = false, _ body: (UserDefaults) -> Void) {
        let name = "ambient-system-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        if migrated { defaults.set(true, forKey: ClosedIslandKeys.migrated) }
        body(defaults)
    }

    @Test func storedChoicesOfTheOlderBuildAreLeftUntouchedAndNewChannelsTakeTheirDefault() {
        suite { defaults in
            defaults.set(true, forKey: ClosedIslandKeys.migrated)
            defaults.set(false, forKey: "notchIdleShowLimits")
            defaults.set(false, forKey: "notchIdleShowBattery")
            defaults.set(true, forKey: "notchIdleShowKeepAwake")
            defaults.set(["battery", "music"], forKey: ClosedIslandKeys.order)
            defaults.set(1, forKey: ClosedIslandKeys.perWing)
            let loaded = ClosedIslandSettings.load(from: defaults)
            #expect(!loaded.isEnabled(AmbientChannel.limits))
            #expect(!loaded.isEnabled(AmbientChannel.battery))
            #expect(loaded.isEnabled(AmbientChannel.keepAwake))
            #expect(loaded.isEnabled(AmbientChannel.claude))  // never written: default on
            #expect(loaded.isEnabled(AmbientChannel.clock) && loaded.isEnabled(AmbientChannel.system) && loaded.isEnabled(AmbientChannel.network))
            #expect(!loaded.isEnabled(AmbientChannel.disk) && !loaded.isEnabled(AmbientChannel.mic))
            #expect(loaded.maxPerWing == 1)
            #expect(loaded.order == ["battery", "music"])
            // Reading never writes: the user's keys are still what they were.
            #expect(defaults.object(forKey: "notchIdleShowClock") == nil)
            #expect(defaults.bool(forKey: "notchIdleShowLimits") == false)
        }
    }

    @Test func aUserWhoSwitchedTheClockOffKeepsItOff() {
        suite { defaults in
            defaults.set(true, forKey: ClosedIslandKeys.migrated)
            defaults.set(false, forKey: "notchIdleShowClock")
            #expect(!ClosedIslandSettings.read(from: defaults).isEnabled(AmbientChannel.clock))
        }
    }

    @Test func theFirstLoadCarriesTheOldChoiceAndWritesEveryKey() {
        suite { defaults in
            defaults.set("none", forKey: ClosedIslandKeys.legacyContent)
            let loaded = ClosedIslandSettings.load(from: defaults)
            #expect(loaded.isEnabled(AmbientChannel.claude) && loaded.isEnabled(AmbientChannel.music))
            #expect(!loaded.isEnabled(AmbientChannel.limits) && !loaded.isEnabled(AmbientChannel.clock))  // "nothing at rest" stays nothing
            #expect(defaults.object(forKey: "notchIdleShowClock") as? Bool == false)
            #expect(defaults.object(forKey: "notchIdleShowVolume") as? Bool == false)
        }
        suite { defaults in
            defaults.set("battery", forKey: ClosedIslandKeys.legacyContent)
            let loaded = ClosedIslandSettings.load(from: defaults)
            #expect(loaded.isEnabled(AmbientChannel.battery) && loaded.isEnabled(AmbientChannel.clock) && loaded.isEnabled(AmbientChannel.network))
        }
        suite { defaults in
            defaults.set("agents", forKey: ClosedIslandKeys.legacyContent)  // what the older build wrote by default
            #expect(ClosedIslandSettings.load(from: defaults) == .standard)
        }
    }

    @Test func theHourCycleRoundTripsAndFallsBackToTheSystem() {
        suite { defaults in
            var settings = ClosedIslandSettings.standard
            settings.clockHours = .h12
            settings.write(to: defaults)
            #expect(ClosedIslandSettings.read(from: defaults).clockHours == .h12)
            defaults.set(24, forKey: ClosedIslandKeys.clockHours)
            #expect(ClosedIslandSettings.read(from: defaults).clockHours == .h24)
            defaults.set(7, forKey: ClosedIslandKeys.clockHours)
            #expect(ClosedIslandSettings.read(from: defaults).clockHours == .system)
        }
    }

    @MainActor @Test func theSettingsPageListsEveryChannelInOrderWithFrenchTitles() {
        suite(migrated: true) { defaults in
            let preferences = ClosedIslandPreferences(defaults: defaults)
            let rows = preferences.rows
            #expect(rows.map(\.channel) == AmbientChannel.userChoices)
            #expect(rows.count == 12)
            #expect(Set(rows.map(\.title)).count == rows.count)
            #expect(rows.allSatisfy { !$0.title.isEmpty && !$0.hint.isEmpty && $0.hint != "Toujours affichées." })
            #expect(rows.first { $0.channel == AmbientChannel.clock }?.title == "Heure au centre")
            #expect(rows.first { $0.channel == AmbientChannel.clock }?.isOn == true)
            #expect(rows.first { $0.channel == AmbientChannel.mic }?.isOn == false)
            preferences.setEnabled(AmbientChannel.mic, true)
            #expect(defaults.bool(forKey: "notchIdleShowMic"))
            preferences.setClockHours(.h24)
            #expect(defaults.integer(forKey: "notchIdleClockHours") == 24)
        }
    }

    /// Regression: the write of a toggle used to be re-read key by key (defaults notify inline on the main thread),
    /// so subscribers saw half-written states and the samplers would start and stop for them.
    @MainActor @Test func aToggleIsPublishedOnceAndNeverHalfWritten() {
        suite(migrated: true) { defaults in
            let preferences = ClosedIslandPreferences(defaults: defaults)
            var seen: [ClosedIslandSettings] = []
            let subscription = preferences.$settings.dropFirst().sink { seen.append($0) }
            preferences.setEnabled(AmbientChannel.system, false)
            preferences.setEnabled(AmbientChannel.mic, true)
            preferences.setClockHours(.h24)
            #expect(seen.count == 3)
            #expect(seen.last?.isEnabled(AmbientChannel.system) == false)
            #expect(seen.last?.isEnabled(AmbientChannel.mic) == true)
            #expect(seen.last?.clockHours == .h24)
            subscription.cancel()
        }
    }

    // MARK: Ten channels, two per wing

    @Test func withTenIndicatorsEachWingShowsTwoAndTheRestRotates() {
        let content = ClosedIslandLayout.resolve(allIndicators(), settings: everything)
        #expect(content.leading.count <= 2 && content.trailing.count <= 2)
        #expect(content.pageCount == 3)  // 11 flowing items, 4 per page
        #expect(content.isRotating)
    }

    @Test func rotatingThroughAllPagesShowsEveryIndicatorExactlyOnce() {
        var seen: [String] = []
        let total = ClosedIslandLayout.resolve(allIndicators(), settings: everything).pageCount
        for step in 0..<total {
            let page = ClosedIslandLayout.resolve(allIndicators(), settings: everything, step: step)
            #expect(page.leading.count <= 2 && page.trailing.count <= 2)
            seen += ids(page.all)
        }
        #expect(Set(seen) == Set(allIndicators().map(\.id)))
        #expect(seen.count == allIndicators().count)  // no one is shown twice
    }

    @Test func aWrongStepWrapsAround() {
        let a = ClosedIslandLayout.resolve(allIndicators(), settings: everything, step: 1)
        let b = ClosedIslandLayout.resolve(allIndicators(), settings: everything, step: 4)
        #expect(a.all == b.all)
        #expect(ClosedIslandLayout.resolve(allIndicators(), settings: everything, step: -2).step == 1)
    }

    @Test func urgentAndPinnedItemsStayOnEveryPage() {
        var input = allIndicators()
        input.append(item("alert.low", channel: AmbientChannel.battery, priority: .alert, urgent: true, wing: .trailing))
        input.append(AmbientReadings.mic())
        for step in 0..<6 {
            let page = ClosedIslandLayout.resolve(input, settings: everything, step: step)
            #expect(page.trailing.first?.id == "alert.low" || page.leading.first?.id == "alert.low")
            #expect(ids(page.all).contains("mic"))
            #expect(page.leading.count <= 2 && page.trailing.count <= 2)
        }
    }

    @Test func disabledChannelsAreSkippedEvenWhenTheirIndicatorsExist() {
        var settings = everything
        settings.enabled.remove(AmbientChannel.network)
        settings.enabled.remove(AmbientChannel.disk)
        let total = ClosedIslandLayout.resolve(allIndicators(), settings: settings).pageCount
        var seen = Set<String>()
        for step in 0..<total { seen.formUnion(ids(ClosedIslandLayout.resolve(allIndicators(), settings: settings, step: step).all)) }
        #expect(seen.isDisjoint(with: AmbientReadings.networkIDs + ["disk"]))
        #expect(seen.contains("system.cpu"))
    }

    @Test func theUserOrderDecidesWhichChannelComesFirst() {
        // Battery, system and disk all live on the right wing: the user's order ranks them there.
        let input = [item("system.cpu", channel: AmbientChannel.system),
                     item("battery", channel: AmbientChannel.battery),
                     item("disk", channel: AmbientChannel.disk)]
        var settings = everything
        settings.order = [AmbientChannel.disk, AmbientChannel.battery, AmbientChannel.system]
        #expect(ids(ClosedIslandLayout.resolve(input, settings: settings, step: 0).trailing) == ["disk", "battery"])
        settings.order = [AmbientChannel.system, AmbientChannel.disk, AmbientChannel.battery]
        #expect(ids(ClosedIslandLayout.resolve(input, settings: settings, step: 0).trailing) == ["system.cpu", "disk"])
    }

    @Test func oneIndicatorPerWingStillCopes() {
        var settings = everything
        settings.maxPerWing = 1
        let content = ClosedIslandLayout.resolve(allIndicators(), settings: settings)
        #expect(content.leading.count == 1 && content.trailing.count == 1)
        #expect(content.pageCount == 6)
    }

    // MARK: Center clock (no notch)

    @Test func withoutANotchTheClockTakesTheCenterAndTheWingsKeepTheirRoom() {
        let content = ClosedIslandLayout.resolve(allIndicators() + [clock()], settings: everything, centered: true)
        #expect(content.center?.id == "clock")
        #expect(!ids(content.all).contains("clock"))
        #expect(content.leading.count == 2 && content.trailing.count == 2)
    }

    @Test func theCenterExistsEvenWhenNothingElseShows() {
        let content = ClosedIslandLayout.resolve([clock()], settings: .standard, centered: true)
        #expect(content.center?.id == "clock")
        #expect(content.leading.isEmpty && content.trailing.isEmpty)
        #expect(!content.isEmpty)
        #expect(!content.isRotating)
    }

    @Test func theDateShowsOnlyWhileTheWingsAreEmpty() {
        let alone = ClosedIslandLayout.resolve([clock()], settings: .standard, centered: true)
        #expect(alone.center?.detail == "dim. 1 nov")
        let busy = ClosedIslandLayout.resolve([clock(), item("system.cpu", channel: AmbientChannel.system)], settings: .standard, centered: true)
        #expect(busy.center?.detail == nil)
        #expect(busy.center?.text == "14:32")
    }

    @Test func aSwitchedOffClockLeavesNoCenterAndNoGhost() {
        var settings = ClosedIslandSettings.standard
        settings.enabled.remove(AmbientChannel.clock)
        let pill = ClosedIslandLayout.resolve([clock(), item("system.cpu", channel: AmbientChannel.system)], settings: settings, centered: true)
        #expect(pill.center == nil)
        #expect(!ids(pill.all).contains("clock"))
        let notched = ClosedIslandLayout.resolve([clock(), item("system.cpu", channel: AmbientChannel.system)], settings: settings)
        #expect(!ids(notched.all).contains("clock"))
    }

    @Test func urgentItemsPinOnTheSideWithRoomNextToTheCenter() {
        // A low battery pins on its own (right) wing, whatever the old preference said, and heads it.
        var input = [item("alert.low", channel: AmbientChannel.battery, priority: .alert, urgent: true, wing: .leading), clock()]
        input += (0..<4).map { item("a\($0)", wing: .leading) }
        let content = ClosedIslandLayout.resolve(input, settings: .standard, centered: true)
        #expect(content.trailing.first?.id == "alert.low")
        #expect(content.center?.id == "clock")
        #expect(content.leading.count <= 2 && content.trailing.count <= 2)
    }

    // MARK: Clock with a hardware notch

    @Test func withANotchTheClockIsTheInnermostItemOfTheLeftWing() {
        let content = ClosedIslandLayout.resolve(allIndicators() + [clock()], settings: everything)
        #expect(content.center == nil)
        #expect(content.leading.last?.id == "clock")  // right beside the notch, Claude and the rest further out
        #expect(content.leading.last?.detail == nil)  // no room for a date beside a notch
        #expect(content.leading.count <= 2 && content.trailing.count <= 2)
    }

    @Test func theNotchedClockCountsAgainstTheLeftWingAndNeverRotates() {
        for step in 0..<5 {
            let content = ClosedIslandLayout.resolve(allIndicators() + [clock()], settings: everything, step: step)
            #expect(content.leading.last?.id == "clock")
            #expect(content.leading.count == 2)
        }
        var oneEach = everything
        oneEach.maxPerWing = 1
        let content = ClosedIslandLayout.resolve([clock(), item("claude", channel: AmbientChannel.claude, priority: .claudeWorking, wing: .leading)],
                                                 settings: oneEach)
        #expect(ids(content.leading) == ["clock"] && ids(content.trailing) == ["claude"])
    }

    // MARK: Width

    @Test func aClockOnlyPillNeedsNoGrowthEvenWithTheDate() {
        let content = ClosedIslandLayout.resolve([clock()], settings: .standard, centered: true)
        #expect(AmbientMetrics.pillExtent(content, now: now) == 0)
        #expect(AmbientMetrics.centerWidth(content.center) + 2 * AmbientMetrics.pillPadding <= NotchGeometry.pillWidth + 2 * NotchGeometry.baseWing)
    }

    @Test func theDateWidensTheCenterSlot() {
        #expect(AmbientMetrics.centerWidth(clock()) > AmbientMetrics.centerWidth(clock(detail: nil)))
        #expect(AmbientMetrics.centerWidth(nil) == 0)
    }

    @Test func theClockStaysCenteredWhenOnlyOneSideHasItems() {
        let left = ClosedIslandContent(leading: [item("a", text: "Mmm"), item("b", text: "Mmm")], trailing: [], center: clock(detail: nil))
        let right = ClosedIslandContent(leading: [], trailing: left.leading, center: clock(detail: nil))
        // The same extent either way: both sides reserve the wider side, so the clock never moves off the middle.
        #expect(AmbientMetrics.pillExtent(left, now: now) == AmbientMetrics.pillExtent(right, now: now))
        #expect(AmbientMetrics.pillExtent(left, now: now) > 0)
    }

    @Test func theCenteredPillIsSymmetricByConstruction() {
        let content = ClosedIslandContent(leading: [item("a", text: "58%")], trailing: [item("b", text: "Mmm"), item("c", text: "Mmm")],
                                          center: clock(detail: nil))
        let extent = AmbientMetrics.pillExtent(content, now: now)
        let width = NotchGeometry.pillWidth + 2 * (NotchGeometry.baseWing + extent)
        let middle = AmbientMetrics.centerWidth(content.center)
        let side = (width - middle) / 2
        let widest = max(AmbientMetrics.groupWidth(content.leading, now: now), AmbientMetrics.groupWidth(content.trailing, now: now))
        #expect(side >= widest + AmbientMetrics.centerGap + AmbientMetrics.pillPadding - 0.5)
    }

    @Test func fittedSidesNeverPushThePillPastItsWidestExtent() {
        let wide = (0..<2).map { item("w\($0)", text: String(repeating: "M", count: 8)) }
        let room = AmbientMetrics.pillSideLimit(center: clock(detail: nil)) + 2 * AmbientMetrics.wingPadding
        let fitted = ClosedIslandContent(
            leading: AmbientMetrics.fitted(wide, width: room, now: now), trailing: AmbientMetrics.fitted(wide, width: room, now: now),
            center: clock(detail: nil))
        #expect(AmbientMetrics.groupWidth(fitted.leading, now: now) <= AmbientMetrics.pillSideLimit(center: clock(detail: nil)))
        #expect(AmbientMetrics.pillExtent(fitted, now: now) <= NotchGeometry.maxWingExtent)
    }

    @Test func aNotchedWingWithTheClockAndAnotherIndicatorStaysWithinTheCap() {
        let content = ClosedIslandContent(leading: [clock(detail: nil), item("a", text: "Mmmmmm")], trailing: [])
        #expect(AmbientMetrics.notchedExtent(content, now: now) <= NotchGeometry.maxWingExtent)
    }

    @Test func aGlyphlessElementReservesNoGlyphAndABarReservesItsWidth() {
        let text = AmbientMetrics.elementWidth(clock(detail: nil), now: now)
        #expect(text == AmbientMetrics.textSlot(clock(detail: nil), now: now))
        let volume = AmbientReadings.volume(level: 0.5, muted: false)
        let expected = AmbientMetrics.glyphSize + AmbientMetrics.iconGap + AmbientMetrics.barWidth
            + AmbientMetrics.iconGap + AmbientMetrics.textSlot(volume, now: now)
        #expect(AmbientMetrics.elementWidth(volume, now: now) == expected)
    }

    // MARK: The center follows the screen kind

    @MainActor @Test func theCenterMovesTheClockWhenTheScreenGainsANotch() {
        suite(migrated: true) { defaults in
            let center = AmbientCenter(activity: ActivityCenter(), preferences: ClosedIslandPreferences(defaults: defaults), isNotched: false,
                                       sleep: { _ in try await Task.sleep(for: .seconds(3600)) }, now: { now })
            center.post(clock())
            #expect(center.content.center?.id == "clock")
            #expect(center.content.leading.isEmpty)
            center.isNotched = true
            #expect(center.content.center == nil)
            #expect(center.content.leading.first?.id == "clock")
        }
    }

    @MainActor @Test func theCenterReportsAWiderPanelWhenSidesAppear() {
        suite(migrated: true) { defaults in
            let center = AmbientCenter(activity: ActivityCenter(), preferences: ClosedIslandPreferences(defaults: defaults), isNotched: false,
                                       sleep: { _ in try await Task.sleep(for: .seconds(3600)) }, now: { now })
            center.post(clock())
            #expect(center.widthProxy.layout.leading == nil)  // the idle pill needs no growth
            for index in 0..<4 { center.post(item("w\(index)", channel: AmbientChannel.system, text: "Mmmmmmmm", wing: index < 2 ? .leading : .trailing)) }
            #expect(center.widthProxy.layout.leading != nil)
        }
    }
}
