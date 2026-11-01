import AppKit
import Foundation
import IslandKit
import IslandTestSupport
import SwiftUI
import Testing
@testable import ShellKit

/// Page-switch cost of the Settings window. Windows are created and never ordered front: nothing shows.
@MainActor
@Suite(.serialized) struct SettingsPerformanceTests {
    private func makeEnv(_ b: (defaults: UserDefaults, cleanup: () -> Void)) -> SettingsEnvironment {
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-perf-marker-\(UUID().uuidString)"))
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all, defaults: b.defaults, crashMarker: marker)
        return SettingsEnvironment(
            registry: registry, defaults: b.defaults, sheetTabs: [:], openPermission: { _ in }, relaunch: nil,
            login: LoginItemModel(service: StaticLoginService(), defaults: b.defaults),
            backup: SettingsBackup(defaults: b.defaults, domain: "perf",
                                 directory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mis-perf-backups-\(UUID().uuidString)")))
    }

    /// Hosts a view in an unordered window and returns the milliseconds that mounting + layout took.
    private func mountMilliseconds<V: View>(_ view: V) -> Double {
        let clock = ContinuousClock()
        let start = clock.now
        let host = NSHostingView(rootView: view.frame(width: 700, height: 640))
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 640)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let d = clock.now - start
        window.contentView = nil
        return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }

    @Test func everyPageMountsWithinBudget() {
        let b = TestDefaults.make(); defer { b.cleanup() }
        let env = makeEnv(b)
        _ = mountMilliseconds(SettingsPageView(pageID: "general", env: env))  // warm-up: fonts, first SwiftUI use
        let scaleBefore = LoadScale.measure()
        var timings: [(String, Double)] = []
        for page in SettingsPageCatalog.all {
            timings.append((page.id, mountMilliseconds(SettingsPageView(pageID: page.id, env: env))))
        }
        let sorted = timings.sorted { $0.1 > $1.1 }
        let total = timings.map(\.1).reduce(0, +)
        let worst = sorted.prefix(5).map { "\($0.0)=\(String(format: "%.1f", $0.1))ms" }.joined(separator: " ")
        print("PERF pages=\(timings.count) mean=\(String(format: "%.1f", total / Double(timings.count)))ms worst: \(worst)")
        // Debug build, offscreen, first mount of each page. Measured after the fixes: mean 17 ms, worst 53 ms
        // (before: mean 32 ms, worst 510 ms). Budgets leave room for a loaded machine; the 30 ms goal is
        // met by 56 of 67 pages in debug, release builds are several times faster.
        // Budgets (100 ms a page, 30 ms mean) are multiplied by how much slower than idle this machine measured
        // before and after the run, so another build running alongside cannot fail the test.
        let scale = max(scaleBefore, LoadScale.measure())
        // One page can take twice its usual time to a single scheduler hiccup (seen: 135 ms against a 55 ms worst);
        // the per-page ceiling is 250 ms scaled, the mean below is what catches a general slowdown.
        let slow = timings.filter { $0.1 > 250 * scale }.map { "\($0.0) \(String(format: "%.1f", $0.1))ms" }
        #expect(slow.isEmpty, "pages over \(250 * scale) ms (load scale \(scale)): \(slow)")
        #expect(total / Double(timings.count) < 30 * scale, "mean page mount over \(30 * scale) ms (load scale \(scale))")
    }

    @Test func switchingPagesInTheWholeWindowIsFast() {
        let b = TestDefaults.make(); defer { b.cleanup() }
        let env = makeEnv(b)
        let router = SettingsRouter(defaults: b.defaults)
        let host = NSHostingView(rootView: SettingsRootView(env: env, router: router))
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 640)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let clock = ContinuousClock()
        let scaleBefore = LoadScale.measure()
        var samples: [Double] = []
        for id in ["menubar", "keepawake", "radial", "advanced", "dockclicks", "general", "shelf", "island"] {
            let start = clock.now
            router.open(id)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            let d = clock.now - start
            samples.append(Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15)
        }
        window.contentView = nil
        print("PERF switch samples(ms, incl. 20ms runloop)=\(samples.map { String(format: "%.0f", $0) })")
        // 120 ms per switch on an idle machine, scaled by the measured load (before and after).
        let scale = max(scaleBefore, LoadScale.measure())
        #expect(samples.allSatisfy { $0 < 120 * scale }, "load scale \(scale)")
    }

    @Test func pollerDoesNotPublishWhenNothingChanged() {
        let b = TestDefaults.make(); defer { b.cleanup() }
        let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mis-perf-marker-\(UUID().uuidString)"))
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all, defaults: b.defaults, crashMarker: marker)
        var fired = 0
        func watch() {
            withObservationTracking { _ = registry.capabilities } onChange: { fired += 1 }
        }
        watch()
        registry.refreshCapabilities()
        registry.refreshCapabilities()
        #expect(fired == 0, "an unchanged poll must not invalidate views")
    }

    @Test func searchIndexIsBuiltOnce() {
        let before = SettingsSearchIndex.buildCount
        for _ in 0..<20 { _ = SettingsSearchIndex.shared.filter(query: "son") }
        _ = SettingsSearchIndex.shared.sections
        _ = SettingsPageCatalog.page("general")
        #expect(SettingsSearchIndex.buildCount - before <= 1)
        #expect(SettingsSearchIndex.buildCount == 1)
        #expect(SettingsSearchIndex.shared.filter(query: "son").map(\.id)
                == SettingsSearch.filter(SettingsPageCatalog.all, query: "son").map(\.id))
    }
}

@MainActor
private struct StaticLoginService: LoginItemService {
    var status: LoginItemStatus { .disabled }
    func register() throws {}
    func unregister() throws {}
    func openSystemSettings() {}
}
