import AppKit
import Foundation
import IslandTestSupport
import IslandUI
import SwiftUI
import Testing
@testable import IslandKit
@testable import ShellKit

/// Hitch harness and budgets: the real `IslandShellView` (closed strip, `HomeIslandContent`, Home, Explorer, a
/// page) and the real Settings window in invisible windows, driven like a user, while `HitchProbe` times every
/// pass of the main run loop. `swift test --filter IslandFluidityTests` prints one `FLUID` line per scenario:
/// `n` passes, `over8` passes over 8 ms, median, p95 and worst, in wall milliseconds, then the same worst pass
/// in main-thread CPU milliseconds.
///
/// Budgets are on main-thread CPU time (a loaded machine preempts the thread, which inflates the wall clock but
/// barely the CPU time), on medians and p95 (never one sample), and sit at 2.5 to 4 times what a debug build
/// measured on an idle Apple Silicon machine. A release build is faster; the build under test is usually debug.
/// What the numbers were before the fixes is in the report that came with this file, not in the assertions.
@MainActor
@Suite(.serialized) struct IslandFluidityTests {
    struct Bench {
        let rig: IslandRig
        let context: ShellContext
        let ambient: AmbientCenter
        let probe: HitchProbe
        let cleanup: () -> Void
    }

    /// A page that costs about what a feature page costs to mount: forty rows in a scroll view.
    private struct BusyPage: View {
        var body: some View {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(0..<40, id: \.self) { i in
                        HStack {
                            Circle().fill(.white.opacity(0.2)).frame(width: 18, height: 18)
                            Text("Row \(i)").font(.system(size: 11))
                            Spacer()
                            Text("\(i * 37)").font(.system(size: 11).monospacedDigit())
                        }
                        .padding(8)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }

    private func makeBench() -> Bench {
        let bench = TestDefaults.make()
        let marker = CrashMarker(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("mis-fluid-marker-\(UUID().uuidString)"))
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all, defaults: bench.defaults, crashMarker: marker)
        let tabs = ShellDescriptors.all.compactMap { d in
            d.tabID.map { id in
                IslandTab(id: id, title: d.title, systemImage: d.systemImage) {
                    id == "agents" ? AnyView(BusyPage()) : AnyView(Color.clear)
                }
            }
        }
        let table = QuickActionTable()
        for id in QuickAccessCatalog.defaultIDs { table.register(id) {} }
        let home = HomeModel(
            defaults: bench.defaults,
            volume: LevelBackend(read: { 0.45 }, write: { _ in true }, unavailableReason: "x"),
            brightness: LevelBackend(read: { 0.75 }, write: { _ in true }, unavailableReason: "x"),
            keyboardLight: LevelBackend(read: { 0.9 }, write: { _ in true }, unavailableReason: "x"))
        let ambient = AmbientCenter(activity: ActivityCenter(), isNotched: true)
        let context = ShellContext(
            tabs: tabs, registry: registry, navigation: ShellNavigation(),
            quickAccess: QuickAccessModel(defaults: bench.defaults, table: table), home: home,
            closedStrip: { AnyView(ClosedStrip(ambient: ambient)) })
        let rig = IslandRig(context: context)
        let probe = HitchProbe()
        probe.start(captureAll: true)
        return Bench(rig: rig, context: rig.context, ambient: ambient, probe: probe,
                     cleanup: { rig.close(); probe.stop(); bench.cleanup(); marker.clear() })
    }

    /// Lets the run loop work for `seconds`. No explicit layout calls: only what the app itself would do.
    private func pump(_ seconds: TimeInterval) async {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            try? await Task.sleep(for: .milliseconds(4))
            RunLoop.current.run(until: Date().addingTimeInterval(0.002))
        }
    }

    private func median(_ values: [Double]) -> Double { HitchStats.percentile(sorted: values.sorted(), 0.5) }
    private func f(_ value: Double) -> String { String(format: "%.1f", value) }

    /// What one scenario produced: wall stats, CPU stats and the CPU spent in total.
    struct Result {
        let wall: HitchStats
        let cpu: HitchStats
        let cpuTotal: Double
        var summary: String { "\(wall.line) | cpu max=\(String(format: "%.1f", cpu.worst)) p95=\(String(format: "%.1f", cpu.p95)) total=\(String(format: "%.0f", cpuTotal))" }
    }

    private func run(_ label: String, _ probe: HitchProbe, settle: TimeInterval = 0.15, duration: TimeInterval,
                     _ action: () -> Void = {}) async -> Result {
        await pump(settle)
        probe.reset()
        action()
        await pump(duration)
        let result = Result(wall: probe.stats(), cpu: probe.cpuStats(), cpuTotal: probe.capturedCPUMilliseconds.reduce(0, +))
        print("FLUID \(label.padding(toLength: 30, withPad: " ", startingAt: 0)) \(result.summary)")
        return result
    }

    /// Runs a scenario until it is inside its budget, at most `attempts` times, and records the failures of the
    /// last attempt only. The main thread is shared with every other main-actor test of the process, and a
    /// snapshot test that blocks it for 100 ms shows up here as a hitch: noise only ever adds time, so the
    /// best of a few attempts is the fair number, and a real regression fails every attempt.
    private func budget(_ name: String, attempts: Int = 6, _ scenario: () async -> [String]) async {
        var last: [String] = []
        for attempt in 1...attempts {
            last = await scenario()
            if last.isEmpty { return }
            print("FLUID \(name): attempt \(attempt) over budget (\(last[0])); the main thread is shared, trying again")
            await pump(1.0)
        }
        for failure in last { Issue.record("\(name): \(failure) (in each of \(attempts) attempts)") }
    }

    // MARK: - The island

    @Test func anIdleIslandDoesNotWakeTheMainThreadForWork() async {
        await budget("idle island") {
            let b = makeBench(); defer { b.cleanup() }
            await pump(0.5)
            let closed = await run("idle closed 2 s", b.probe, duration: 2)
            b.rig.state.isOpen = true
            await pump(1.0)
            let open = await run("idle open 2 s", b.probe, duration: 2)
            var failures: [String] = []
            for (name, r) in [("closed", closed), ("open", open)] {
                if r.cpu.overThreshold > 0 { failures.append("\(name): \(r.cpu.overThreshold) passes over 8 ms of CPU while nothing happens") }
                if r.cpu.p95 >= 3 { failures.append("\(name): p95 \(f(r.cpu.p95)) ms") }
            }
            return failures
        }
    }

    @Test func openAndCloseWhileThePillAnimatesStayInBudget() async {
        await budget("open/close with a live pill") {
            let b = makeBench(); defer { b.cleanup() }
            await pump(0.5)
            b.ambient.post(AmbientIndicator(id: "music", channel: AmbientChannel.music, symbol: "waveform", text: "A rather long track title",
                                            priority: .music, wing: .trailing, glyph: .equalizer))
            b.ambient.post(AmbientIndicator(id: "claude", channel: AmbientChannel.claude, symbol: "sparkles", status: .info,
                                            priority: .claudeWorking, wing: .leading, isBusy: true,
                                            clockSince: Date().addingTimeInterval(-90), label: "Claude travaille"))
            let steady = await run("closed, busy ring + equalizer", b.probe, duration: 2)
            var worst: [Double] = []
            for _ in 0..<3 {
                worst.append(await run("open (live pill)", b.probe, duration: 0.9) { b.rig.state.isOpen = true }.cpu.worst)
                worst.append(await run("close (live pill)", b.probe, duration: 0.9) { b.rig.state.isOpen = false }.cpu.worst)
            }
            var failures: [String] = []
            if steady.cpu.p95 >= 6 { failures.append("the live pill costs p95 \(f(steady.cpu.p95)) ms per pass") }
            if median(worst) >= 20 { failures.append("median worst pass \(f(median(worst))) ms") }
            return failures
        }
    }

    @Test func switchingRoutesStaysInBudget() async {
        await budget("route switches") {
            let b = makeBench(); defer { b.cleanup() }
            let nav = b.context.navigation
            b.rig.state.isOpen = true
            await pump(0.8)
            var worst: [String: [Double]] = [:]
            for _ in 0..<5 {
                for (label, action) in [("home->explorer", { nav.toggleExplore() }), ("explorer->page", { nav.open(tabID: "agents") }),
                                        ("page->home", { nav.goHome() })] as [(String, () -> Void)] {
                    worst[label, default: []].append(await run(label, b.probe, settle: 0.2, duration: 0.5, action).cpu.worst)
                }
            }
            return worst.sorted { $0.key < $1.key }.compactMap { label, values in
                median(values) < 60 ? nil : "\(label): median worst pass \(f(median(values))) ms of CPU, all \(values.map(f))"
            }
        }
    }

    @Test func publishesThatChangeNothingCostNothing() async {
        await budget("publishes") {
            let b = makeBench(); defer { b.cleanup() }
            await pump(0.5)
            let home = b.context.home
            let registry = b.context.registry
            let kinds: [(String, (Int) -> Void)] = [
                ("track same value", { _ in home.track = HomeTrack(title: "Same", isPlaying: true, progress: 0.4) }),
                ("levels refresh", { _ in home.refreshLevels() }),
                ("capabilities refresh", { _ in registry.refreshCapabilities() }),
                ("track progress moves", { n in home.track = HomeTrack(title: "Same", isPlaying: true, progress: Double(n % 100) / 100) }),
            ]
            var failures: [String] = []
            for open in [false, true] {
                b.rig.state.isOpen = open
                await pump(1.2)
                for (name, publish) in kinds {
                    var n = 0
                    b.probe.reset()
                    // Ten a second for two seconds: faster than any source in the app.
                    let end = Date().addingTimeInterval(2)
                    while Date() < end {
                        n += 1
                        publish(n)
                        await pump(0.1)
                    }
                    let cpu = b.probe.cpuStats()
                    let label = "\(open ? "open  " : "closed") \(name)"
                    print("FLUID \(label.padding(toLength: 30, withPad: " ", startingAt: 0)) \(b.probe.stats().line) | cpu max=\(f(cpu.worst)) p95=\(f(cpu.p95))")
                    if cpu.p95 >= 6 { failures.append("\(label): p95 \(f(cpu.p95)) ms of CPU") }
                }
            }
            return failures
        }
    }

    // MARK: - Settings

    @Test func settingsPageSwitchesStayInBudget() async {
        await budget("settings window") {
            let bench = TestDefaults.make()
            defer { bench.cleanup() }
            let marker = CrashMarker(url: FileManager.default.temporaryDirectory
                .appendingPathComponent("mis-fluid-settings-\(UUID().uuidString)"))
            defer { marker.clear() }
            let registry = FeatureRegistry(descriptors: ShellDescriptors.all, defaults: bench.defaults, crashMarker: marker)
            let env = SettingsEnvironment(
                registry: registry, defaults: bench.defaults, sheetTabs: [:], openPermission: { _ in }, relaunch: nil,
                login: LoginItemModel(service: FluidLoginService(), defaults: bench.defaults),
                backup: SettingsBackup(defaults: bench.defaults, domain: "fluid",
                                       directory: FileManager.default.temporaryDirectory.appendingPathComponent("mis-fluid-backups-\(UUID().uuidString)")))
            let router = SettingsRouter(defaults: bench.defaults)
            let host = NSHostingView(rootView: SettingsRootView(env: env, router: router))
            host.frame = NSRect(x: 0, y: 0, width: 900, height: 640)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.setFrameOrigin(CGPoint(x: -30_000, y: -30_000))
            window.alphaValue = 0
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            let probe = HitchProbe()
            probe.start(captureAll: true)
            defer { probe.stop() }
            await pump(0.6)
            var worst: [Double] = [], total: [Double] = []
            for id in ["general", "menubar", "keepawake", "advanced", "dockclicks", "shelf", "island", "general"] {
                let r = await run("settings page \(id)", probe, settle: 0.1, duration: 0.35) { router.open(id) }
                worst.append(r.cpu.worst)
                total.append(r.cpuTotal)
            }
            print("FLUID settings pages: cpu-worst median=\(f(median(worst))) cpu-total median=\(f(median(total)))")
            // A switch flipped in the hub redraws the hub, not the window.
            router.open("features")
            await pump(0.5)
            var flips: [Double] = []
            for id in ["clipboard", "shelf", "monitor", "dock"] {
                flips.append(await run("settings toggle \(id)", probe, settle: 0.1, duration: 0.3) {
                    registry.switches[id] = !(registry.switches[id] ?? false)
                }.cpu.worst)
            }
            var failures: [String] = []
            if median(worst) >= 70 { failures.append("page switch: median worst pass \(f(median(worst))) ms of CPU") }
            if median(total) >= 120 { failures.append("page switch: median CPU \(f(median(total))) ms") }
            if median(flips) >= 30 { failures.append("hub switch: median worst pass \(f(median(flips))) ms of CPU") }
            return failures
        }
    }

    // MARK: - System reads

    @Test func readingTheSystemLevelsIsCheapOnThisMachine() {
        let clock = ContinuousClock()
        var samples: [Double] = []
        _ = SystemVolume.backend.read()
        _ = SystemBrightness.backend.read()
        for _ in 0..<60 {
            let start = clock.now
            _ = SystemVolume.backend.read()
            _ = SystemBrightness.backend.read()
            let d = clock.now - start
            samples.append(Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15)
        }
        let stats = HitchStats(milliseconds: samples)
        print("FLUID level reads (volume+brightness) \(stats.line)")
        #expect(stats.median < 4, "median \(stats.median) ms on the main thread, once a second while open")
    }
}

@MainActor
private struct FluidLoginService: LoginItemService {
    var status: LoginItemStatus { .disabled }
    func register() throws {}
    func unregister() throws {}
    func openSystemSettings() {}
}
