import Foundation
import IslandKit
import IslandTestSupport
import SwiftUI
import Testing
@testable import ShellKit

@MainActor
@Suite struct StatusChipFeedTests {
    private func feed(_ sources: [FakeStatusChipSource], layout: StatusChipLayout = .initial,
                      isEnabled: Bool = true) -> StatusChipFeed {
        StatusChipFeed(sources: sources, layout: layout, isEnabled: isEnabled)
    }

    // MARK: Fan-out

    @Test func nothingRunsBeforeStart() {
        let network = FakeStatusChipSource(.network, first: .sample(.network))
        let feed = feed([network])
        #expect(network.startCount == 0 && !network.isRunning)
        #expect(feed.readings.isEmpty && !feed.isRunning)
    }

    @Test func startAndStopFanOutOnceToEveryEnabledSource() {
        let network = FakeStatusChipSource(.network, first: .sample(.network, "Wi-Fi"))
        let load = FakeStatusChipSource(.load, first: .sample(.load, "CPU 10 %"))
        let disk = FakeStatusChipSource(.disk, first: .sample(.disk))  // not in the default layout
        let feed = feed([network, load, disk])
        feed.start()
        feed.start()  // idempotent
        #expect(network.startCount == 1 && load.startCount == 1)
        #expect(disk.startCount == 0, "a chip that is not enabled costs nothing")
        #expect(feed.readings.map(\.primary) == ["Wi-Fi", "CPU 10 %"])
        feed.stop()
        feed.stop()
        #expect(network.stopCount == 1 && load.stopCount == 1 && disk.stopCount == 0)
        #expect(feed.readings.isEmpty && !network.isRunning)
    }

    @Test func aReopenedFeedStartsTheSourcesAgain() {
        let network = FakeStatusChipSource(.network, first: .sample(.network))
        let feed = feed([network])
        feed.start(); feed.stop(); feed.start()
        #expect(network.startCount == 2 && network.stopCount == 1 && network.isRunning)
        #expect(feed.readings.count == 1)
    }

    @Test func theMasterSwitchStopsAndRestartsRunningSources() {
        let network = FakeStatusChipSource(.network, first: .sample(.network))
        let feed = feed([network])
        feed.start()
        feed.isEnabled = false
        #expect(network.stopCount == 1 && feed.readings.isEmpty && !feed.hasSlot)
        feed.isEnabled = true
        #expect(network.startCount == 2 && feed.readings.count == 1 && feed.hasSlot)
    }

    @Test func switchingAChipOnOrOffStartsOrStopsOnlyThatSource() {
        let network = FakeStatusChipSource(.network, first: .sample(.network, "Wi-Fi"))
        let disk = FakeStatusChipSource(.disk, first: .sample(.disk, "412 Go"))
        let feed = feed([network, disk], layout: StatusChipLayout(kinds: [.network]))
        feed.start()
        feed.layout.enable(.disk)
        #expect(disk.startCount == 1 && network.startCount == 1)
        #expect(feed.readings.map(\.kind) == [.network, .disk])
        feed.layout.disable(.network)
        #expect(network.stopCount == 1 && disk.stopCount == 0)
        #expect(feed.readings.map(\.kind) == [.disk])
    }

    // MARK: Readings

    @Test func readingsFollowTheLayoutOrderAndRebuildOnAChange() {
        let network = FakeStatusChipSource(.network, first: .sample(.network, "Wi-Fi"))
        let load = FakeStatusChipSource(.load, first: .sample(.load, "CPU 10 %"))
        let feed = feed([network, load], layout: StatusChipLayout(kinds: [.load, .network]))
        feed.start()
        #expect(feed.readings.map(\.kind) == [.load, .network])
        feed.layout.move(.network, before: .load)
        #expect(feed.readings.map(\.kind) == [.network, .load])
        load.push(.sample(.load, "CPU 80 %", level: .attention))
        #expect(feed.readings.last?.primary == "CPU 80 %" && feed.readings.last?.level == .attention)
        load.push(nil)
        #expect(feed.readings.map(\.kind) == [.network])
    }

    @Test func aKindWithoutASourceIsSimplyAbsent() {
        let network = FakeStatusChipSource(.network, first: .sample(.network))
        let feed = feed([network], layout: StatusChipLayout(kinds: [.timer, .network, .nextEvent]))
        feed.start()
        #expect(feed.readings.map(\.kind) == [.network])
        #expect(feed.availableKinds == [.network])
    }

    @Test func theLastSourceOfAKindWins() {
        let early = FakeStatusChipSource(.load, first: .sample(.load, "early"))
        let late = FakeStatusChipSource(.load, first: .sample(.load, "late"))
        let feed = feed([early, late])
        feed.start()
        #expect(feed.sources.count == 1)
        #expect(early.startCount == 0 && late.startCount == 1)
        #expect(feed.readings.map(\.primary) == ["late"])
    }

    @Test func replacingTheSourcesStopsTheOldOnes() {
        let old = FakeStatusChipSource(.network, first: .sample(.network, "old"))
        let feed = feed([old])
        feed.start()
        let new = FakeStatusChipSource(.network, first: .sample(.network, "new"))
        feed.setSources([new])
        #expect(old.stopCount == 1 && new.startCount == 1)
        #expect(feed.readings.map(\.primary) == ["new"])
    }

    // MARK: The slot (what the home keeps room for)

    @Test func theSlotNeedsTheSwitchAndAnEnabledChipWithASource() {
        let network = FakeStatusChipSource(.network)
        #expect(feed([]).hasSlot == false)
        #expect(feed([network]).hasSlot)
        #expect(feed([network], isEnabled: false).hasSlot == false)
        #expect(feed([network], layout: StatusChipLayout(kinds: [.disk])).hasSlot == false)
        #expect(feed([network], layout: StatusChipLayout(kinds: [])).hasSlot == false)
    }

    @Test func theSlotDoesNotWaitForTheFirstReading() {
        let feed = feed([FakeStatusChipSource(.network)])
        #expect(feed.hasSlot && feed.readings.isEmpty)
    }

    // MARK: HomeModel

    private func model(_ defaults: UserDefaults) -> HomeModel {
        HomeModel(defaults: defaults, volume: LevelBackend.unsupported("x"), brightness: LevelBackend.unsupported("x"))
    }

    @Test func theModelPersistsTheLayoutAndTheSwitch() {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        let m = model(bench.defaults)
        #expect(m.showsStatusChips && m.statusChipLayout == .initial)
        m.statusChipLayout.enable(.disk)
        m.statusChipLayout.move(.disk, before: .network)
        m.showsStatusChips = false
        let again = model(bench.defaults)
        #expect(again.statusChipLayout.kinds == [.disk, .network, .load, .nextEvent])
        #expect(!again.showsStatusChips)
        #expect(!again.statusChips.isEnabled && again.statusChips.layout == again.statusChipLayout)
    }

    @Test func theModelMirrorsTheLayoutAndSwitchIntoTheFeed() {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        let m = model(bench.defaults)
        m.statusChipLayout.disable(.load)
        #expect(m.statusChips.layout.kinds == [.network, .nextEvent])
        m.showsStatusChips = false
        #expect(!m.statusChips.isEnabled)
    }

    @Test func theStoredLayoutUsesTheVersionedJSON() throws {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        let m = model(bench.defaults)
        m.statusChipLayout.disable(.nextEvent)
        let data = try #require(bench.defaults.data(forKey: HomeModel.Keys.statusChips))
        #expect(StatusChipLayout.decode(data).kinds == [.network, .load])
        #expect(bench.defaults.object(forKey: HomeModel.Keys.showsStatusChips) == nil, "the switch is written only when it changes")
    }

    @Test func garbageInDefaultsFallsBackToTheDefaults() {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        bench.defaults.set(Data("junk".utf8), forKey: HomeModel.Keys.statusChips)
        bench.defaults.set("yes", forKey: HomeModel.Keys.showsStatusChips)
        let m = model(bench.defaults)
        #expect(m.statusChipLayout == .initial && m.showsStatusChips)
    }

    @Test func theHomeKeepsRoomForTheRowOnlyWhileItHasASlot() {
        let bench = TestDefaults.make()
        defer { bench.cleanup() }
        let m = model(bench.defaults)
        let plain = m.homeBody.height
        m.statusChips.setSources([FakeStatusChipSource(.network)])
        #expect(m.homeBody.height == plain + HomeGeometry.statusChipSpace)
        m.showsStatusChips = false
        #expect(m.homeBody.height == plain)
        m.showsStatusChips = true
        m.statusChipLayout.disable(.network)
        m.statusChipLayout.disable(.load)
        m.statusChipLayout.disable(.nextEvent)
        #expect(m.homeBody.height == plain, "no enabled chip, no row")
    }

    // MARK: ShellContext

    @Test func theContextFeedsNetworkLoadAndDiskItselfAndTakesTheAppsSources() {
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: FileManager.default.temporaryDirectory.appendingPathComponent("mis-chip-marker-\(UUID().uuidString)"))
        defer { bench.cleanup(); marker.clear() }
        let registry = FeatureRegistry(descriptors: [], defaults: bench.defaults, crashMarker: marker)
        let home = model(bench.defaults)
        let timer = FakeStatusChipSource(.timer)
        _ = ShellContext(tabs: [], registry: registry, navigation: ShellNavigation(),
                         quickAccess: QuickAccessModel(defaults: bench.defaults, table: QuickActionTable()),
                         home: home, statusSources: { [timer] })
        #expect(home.statusChips.availableKinds == [.network, .load, .disk, .timer])
        // An app source of a built-in kind replaces it.
        let load = FakeStatusChipSource(.load)
        let replaced = ShellContext(tabs: [], registry: registry, navigation: ShellNavigation(),
                                    quickAccess: QuickAccessModel(defaults: bench.defaults, table: QuickActionTable()),
                                    home: home, statusSources: { [load] })
        #expect(replaced.home.statusChips.sources.contains { $0 === load })
        #expect(replaced.home.statusChips.sources.filter { $0.kind == .load }.count == 1)
    }

    @Test func theBuiltInChipsOpenTheMonitorOnlyWhenThereIsAMonitorTab() async throws {
        for withMonitor in [true, false] {
            let bench = TestDefaults.make()
            let marker = CrashMarker(url: FileManager.default.temporaryDirectory.appendingPathComponent("mis-chip-marker-\(UUID().uuidString)"))
            defer { bench.cleanup(); marker.clear() }
            let registry = FeatureRegistry(descriptors: [], defaults: bench.defaults, crashMarker: marker)
            let navigation = ShellNavigation()
            let tabs = withMonitor
                ? [IslandTab(id: "monitor", title: "Moniteur", systemImage: "chart.line.uptrend.xyaxis") { AnyView(EmptyView()) }]
                : []
            let home = model(bench.defaults)
            _ = ShellContext(tabs: tabs, registry: registry, navigation: navigation,
                             quickAccess: QuickAccessModel(defaults: bench.defaults, table: QuickActionTable()), home: home)
            // The disk source reads once at start: take its first reading and tap its action.
            let disk = try #require(home.statusChips.sources.first { $0.kind == .disk })
            disk.start()
            defer { disk.stop() }
            for _ in 0..<300 where disk.reading == nil { try await Task.sleep(for: .milliseconds(10)) }
            let reading = try #require(disk.reading)
            #expect(reading.actions.isEmpty == !withMonitor)
            reading.actions.first?.handler()
            #expect(navigation.route == (withMonitor ? .page("monitor") : .home))
        }
    }
}
