import AppKit
import Foundation
import Testing
@testable import PortKit

/// Lane W6-B: the menu bar metrics host with a FAKE status bar, sampler, popover and icon hook. Nothing here creates
/// an `NSStatusItem`, starts the monitor or reads a sensor.
@MainActor
@Suite(.serialized) struct MenuBarMetricsTests {
    @MainActor final class FakeSurface: MenuBarMetricSurface {
        var titles: [String] = []
        var removed = false
        func show(title: NSAttributedString) { titles.append(title.string) }
        func remove() { removed = true }
    }

    @MainActor final class FakePresenter: MenuBarMetricDetailPresenter {
        var onClose: (() -> Void)?
        var isShown = false
        var shown: [MetricDetailKind] = []
        func show(kind: MetricDetailKind, below surface: MenuBarMetricSurface,
                  setNeeds: @escaping (SystemMonitorPanelNeeds) -> Void) {
            isShown = true
            shown.append(kind)
        }
        func close() {
            isShown = false
            onClose?()
        }
    }

    @MainActor final class Bench {
        var snapshot = SystemSnapshot()
        var surfaces: [String: FakeSurface] = [:]
        var created: [String] = []
        var clicks: [String: @MainActor (MenuBarMetricSurface, NSEvent?) -> Void] = [:]
        var monitorActive: [Bool] = []
        var needs: [SystemMonitorPanelNeeds] = []
        var now: TimeInterval = 100
        var settingsOpened = 0
        var iconVisible: [Bool] = []
        let presenter = FakePresenter()

        func host(_ defaults: UserDefaults) -> MenuBarMetricsHost {
            MenuBarMetricsHost(environment: MenuBarMetricsHost.Environment(
                defaults: { defaults },
                strings: { L10n.shared.s },
                snapshot: { [unowned self] in snapshot },
                setMenuBarActive: { [unowned self] in monitorActive.append($0) },
                setPanelNeeds: { [unowned self] in needs.append($0) },
                makeSurface: { [unowned self] id, click in
                    let surface = FakeSurface()
                    surfaces[id] = surface
                    created.append(id)
                    clicks[id] = click
                    return surface
                },
                makePresenter: { [unowned self] in presenter },
                openSettings: { [unowned self] in settingsOpened += 1 },
                quit: {},
                now: { [unowned self] in now }))
        }
    }

    /// Every family on, as the registry would say; the defaults pin what the test asks.
    func withFamiliesOn(_ body: (UserDefaults) -> Void) {
        PortHostFixture.isolated { defaults in
            PortHost.availability = { _ in true }
            body(defaults)
        }
    }

    // MARK: The plan

    @Test func nothingPinnedMeansNoItemAndAFamilyThatIsOffHidesItsPinnedMetric() {
        PortHostFixture.isolated { defaults in
            PortHost.availability = { _ in true }
            #expect(MenuBarMetricsPlan.make(defaults: defaults, strings: L10n.shared.s).items.isEmpty)
            defaults.set(true, forKey: DefaultsKey.menuBarCPU)
            #expect(MenuBarMetricsPlan.make(defaults: defaults, strings: L10n.shared.s).items.count == 1)
            PortHost.availability = { $0 == "monitorCPU" ? false : true }
            #expect(MenuBarMetricsPlan.make(defaults: defaults, strings: L10n.shared.s).items.isEmpty,
                    "a pinned metric of a family that is off stops rendering")
        }
    }

    @Test func oneItemHoldsEveryPinnedMetricUnlessTheyAreSeparatedAndThenAUsageKeepsItsTemperature() {
        withFamiliesOn { defaults in
            for key in [DefaultsKey.menuBarCPU, DefaultsKey.menuBarCPUTemperature, DefaultsKey.menuBarMemory] {
                defaults.set(true, forKey: key)
            }
            defaults.set(true, forKey: DefaultsKey.menuBarCombineTemperatures)
            let together = MenuBarMetricsPlan.make(defaults: defaults, strings: L10n.shared.s)
            #expect(together.items.map(\.id) == ["metrics"])
            #expect(together.items[0].metrics == [.cpu, .cpuTemperature, .memory])
            #expect(together.items[0].focus == .cpu)

            defaults.set(true, forKey: DefaultsKey.menuBarSeparateMetrics)
            let apart = MenuBarMetricsPlan.make(defaults: defaults, strings: L10n.shared.s)
            #expect(apart.items.map(\.id) == ["metric.cpu", "metric.memory"], "usage and temperature share one item")
            #expect(apart.items[0].metrics == [.cpu, .cpuTemperature])
            defaults.set(false, forKey: DefaultsKey.menuBarCombineTemperatures)
            let split = MenuBarMetricsPlan.make(defaults: defaults, strings: L10n.shared.s)
            #expect(split.items.map(\.id) == ["metric.cpu", "metric.cpuTemperature", "metric.memory"])
        }
    }

    // MARK: The host

    @Test func theHostDrawsOneTitlePerSampleAndTakesTheSamplerBackWhenNothingIsPinned() {
        withFamiliesOn { defaults in
            let bench = Bench()
            let host = bench.host(defaults)
            host.sync()
            #expect(host.itemIDs.isEmpty && bench.created.isEmpty)
            #expect(bench.monitorActive == [false], "nothing pinned: the sampler is not asked to run")

            defaults.set(true, forKey: DefaultsKey.menuBarCPU)
            bench.snapshot.cpuUsage = 0.42
            host.sync()
            #expect(host.itemIDs == ["metrics"] && bench.created == ["metrics"])
            #expect(bench.monitorActive.last == true)
            let titles = bench.surfaces["metrics"]?.titles ?? []
            #expect(titles.count == 1 && !(titles.first ?? "").isEmpty)

            bench.snapshot.cpuUsage = 0.9
            host.render()
            #expect(bench.created == ["metrics"], "the same item is redrawn, not created twice")
            #expect(bench.surfaces["metrics"]?.titles.count == 2)

            defaults.set(false, forKey: DefaultsKey.menuBarCPU)
            host.sync()
            #expect(host.itemIDs.isEmpty && bench.surfaces["metrics"]?.removed == true)
            #expect(bench.monitorActive.last == false, "the last item went: the sampler stops")
        }
    }

    @Test func aReadingThatSkipsAFewTicksKeepsItsItemBlankAndOneThatStopsForGoodLosesIt() {
        withFamiliesOn { defaults in
            let bench = Bench()
            let host = bench.host(defaults)
            defaults.set(true, forKey: DefaultsKey.menuBarCPU)
            host.sync()
            #expect(bench.created.isEmpty, "a metric that never rendered anything gets no item")
            bench.snapshot.cpuUsage = 0.3
            host.render()
            #expect(host.itemIDs == ["metrics"])
            bench.snapshot.cpuUsage = nil
            let gap = MenuBarSpacingSupport.emptyMetricRendersBeforeRemoval
            for _ in 0..<(gap - 1) { host.render() }
            #expect(host.itemIDs == ["metrics"], "kept, blank, through a short gap")
            #expect(bench.surfaces["metrics"]?.titles.last == "")
            host.render()
            #expect(host.itemIDs.isEmpty && bench.surfaces["metrics"]?.removed == true)
        }
    }

    // MARK: Clicks

    @Test func aLeftClickOpensTheFocusMetricDetailAndAskForItsReadingsAndASecondClickClosesIt() {
        withFamiliesOn { defaults in
            let bench = Bench()
            let host = bench.host(defaults)
            defaults.set(true, forKey: DefaultsKey.menuBarCPU)
            bench.snapshot.cpuUsage = 0.5
            host.sync()
            #expect(host.itemIDs == ["metrics"])
            let surface = bench.surfaces["metrics"]!
            bench.clicks["metrics"]?(surface, nil)
            #expect(bench.presenter.shown == [.cpu] && bench.presenter.isShown)
            #expect(bench.needs.last == MetricDetailKind.cpu.monitorNeeds, "the sampler is asked for the CPU reading")
            bench.clicks["metrics"]?(surface, nil)
            #expect(!bench.presenter.isShown)
            #expect(bench.needs.last == SystemMonitorPanelNeeds.none, "closed: the panel needs go back to nothing")
            #expect(bench.presenter.shown == [.cpu], "a click on an open detail closes it, it does not reopen")
        }
    }

    @Test func theClickThatClosedATransientPopoverDoesNotReopenItButALaterOneDoes() {
        withFamiliesOn { defaults in
            let bench = Bench()
            let host = bench.host(defaults)
            defaults.set(true, forKey: DefaultsKey.menuBarCPU)
            bench.snapshot.cpuUsage = 0.5
            host.sync()
            let surface = bench.surfaces["metrics"]!
            bench.clicks["metrics"]?(surface, nil)
            // The popover closed by itself on the mouse-down (outside click), then the mouse-up arrives.
            bench.presenter.close()
            bench.now += 0.1
            bench.clicks["metrics"]?(surface, nil)
            #expect(bench.presenter.shown == [.cpu], "the closing click is not a reopening click")
            bench.now += 5
            bench.clicks["metrics"]?(surface, nil)
            #expect(bench.presenter.shown == [.cpu, .cpu])
        }
    }

    @Test func aRightClickOpensNoDetailAndTheItemGoingAwayClosesAnOpenOne() {
        withFamiliesOn { defaults in
            let bench = Bench()
            let host = bench.host(defaults)
            defaults.set(true, forKey: DefaultsKey.menuBarCPU)
            bench.snapshot.cpuUsage = 0.5
            host.sync()
            let surface = bench.surfaces["metrics"]!
            let right = NSEvent.mouseEvent(with: .rightMouseUp, location: .zero, modifierFlags: [], timestamp: 0,
                                           windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)
            bench.clicks["metrics"]?(surface, right)
            #expect(bench.presenter.shown.isEmpty, "the context menu is the right click's")
            bench.clicks["metrics"]?(surface, nil)
            #expect(bench.presenter.isShown)
            defaults.set(false, forKey: DefaultsKey.menuBarCPU)
            host.sync()
            #expect(!bench.presenter.isShown, "no item left to hang the popover from")
            #expect(bench.needs.last == SystemMonitorPanelNeeds.none)
        }
    }

    @Test func theContextMenuOffersSettingsAndQuitOnly() {
        #expect(MenuBarMetricsHost.menuTitles == ["Ouvrir Réglages…", "Quitter Mac Island"])
    }

    // MARK: The app icon

    @Test func theAppIconHidesOnlyWhileAMetricShowsAndOnlyWhenAsked() {
        withFamiliesOn { defaults in
            let bench = Bench()
            let host = bench.host(defaults)
            var visible: [Bool] = []
            host.installAppIconVisibility { visible.append($0) }
            #expect(visible == [true], "installing the hook makes the icon visible at once")

            defaults.set(true, forKey: DefaultsKey.menuBarCPU)
            bench.snapshot.cpuUsage = 0.5
            host.sync()
            #expect(visible == [true] && !host.isAppIconHidden, "the option is off: the icon stays")

            defaults.set(true, forKey: DefaultsKey.menuBarHideIconWithMetrics)
            host.sync()
            #expect(visible == [true, false] && host.isAppIconHidden)
            host.render()
            #expect(visible == [true, false], "the same verdict is not repeated")

            bench.snapshot.cpuUsage = nil  // nothing drawn any more
            for _ in 0..<MenuBarSpacingSupport.emptyMetricRendersBeforeRemoval { host.render() }
            #expect(visible.last == true && !host.isAppIconHidden, "no item with a title left: the icon is back")
        }
    }

    @Test func aHookInstalledAfterTheFamiliesStartedStillGetsTheRightVerdict() {
        withFamiliesOn { defaults in
            let bench = Bench()
            let host = bench.host(defaults)
            defaults.set(true, forKey: DefaultsKey.menuBarCPU)
            defaults.set(true, forKey: DefaultsKey.menuBarHideIconWithMetrics)
            bench.snapshot.cpuUsage = 0.5
            host.sync()  // the registry started the families before the app had an icon to lend
            var visible: [Bool] = []
            host.installAppIconVisibility { visible.append($0) }
            #expect(visible == [true, false], "visible first, then the hide rule against what is on screen")
        }
    }

    @Test func removingTheItemsHandsTheIconBackEvenWhenTheOptionStaysOn() {
        withFamiliesOn { defaults in
            let bench = Bench()
            let host = bench.host(defaults)
            var visible: [Bool] = []
            host.installAppIconVisibility { visible.append($0) }
            defaults.set(true, forKey: DefaultsKey.menuBarCPU)
            defaults.set(true, forKey: DefaultsKey.menuBarHideIconWithMetrics)
            bench.snapshot.cpuUsage = 0.5
            host.sync()
            #expect(host.isAppIconHidden)
            PortHost.availability = { _ in false }  // kill switch, safe mode or the family switched off
            host.sync()
            #expect(!host.isAppIconHidden && visible.last == true, "the person can always reach the app")
        }
    }

    // MARK: Popover content

    @Test func everyMetricOpensADetailAndFourOfTheKindsHaveASectionWithTheMatchingReadings() {
        for metric in MenuBarMetric.allCases {
            #expect(MetricDetailKind.allKindsForTest.contains(metric.detailKind), "\(metric)")
        }
        #expect(MenuBarMetricPopover.sectionNeeds(for: .cpu) == SystemMonitorPanelNeeds(system: true))
        #expect(MenuBarMetricPopover.sectionNeeds(for: .connectedDevices) == SystemMonitorPanelNeeds(system: true))
        #expect(MenuBarMetricPopover.sectionNeeds(for: .network) == SystemMonitorPanelNeeds(network: true))
        #expect(MenuBarMetricPopover.sectionNeeds(for: .disk) == SystemMonitorPanelNeeds(disk: true))
        #expect(MenuBarMetricPopover.sectionNeeds(for: .power) == SystemMonitorPanelNeeds(power: true, powerCard: true))
        #expect(MenuBarMetricPopover.sectionNeeds(for: .battery) == SystemMonitorPanelNeeds(power: true, powerCard: true))
        #expect(MenuBarMetricPopover.sectionNeeds(for: .fan) == nil, "fans have their own page, not a panel section here")
    }

    // MARK: Sources

    @Test func theHostWritesNoPreferenceAndNeverPromptsOrReachesTheStandardDomain() throws {
        let root = PortSourceScrubTests.repoRoot
        let source = try String(contentsOf: root.appendingPathComponent("Sources/PortKit/Bridge/MenuBar.swift"), encoding: .utf8)
        let code = source.split(separator: "\n").filter { !$0.drop(while: { $0 == " " }).hasPrefix("//") }.joined(separator: "\n")
        #expect(!code.contains(".set("), "the host reads preferences and never writes one")
        #expect(!code.contains("UserDefaults.standard"))
        #expect(!code.contains("requestAuthorization") && !code.contains("requestAccess"))
        #expect(!code.contains("Process(") && !code.contains("Shell.run"), "no command is run from the menu bar host")
        let compat = try String(contentsOf: root.appendingPathComponent("Sources/PortKit/Compat/StatusItemController.swift"),
                                encoding: .utf8)
        #expect(!compat.contains("UserDefaults.standard.bool"), "the split reads the host's defaults")
    }
}

extension MetricDetailKind {
    /// Every case, for the exhaustiveness check (the type is not `CaseIterable` upstream).
    static let allKindsForTest: [MetricDetailKind] = [.cpu, .gpu, .memory, .network, .disk, .battery, .power, .fan, .connectedDevices]
}
