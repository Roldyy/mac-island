import AppKit
import Foundation
import IslandTestSupport
import Observation
import SwiftUI
import Testing
@testable import IslandKit
@testable import ShellKit

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}

private final class LevelProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var level = 0.5
    var reads: Int { lock.lock(); defer { lock.unlock() }; return count }
    var current: Double {
        get { lock.lock(); defer { lock.unlock() }; return level }
        set { lock.lock(); level = newValue; lock.unlock() }
    }
    func read() -> Double { lock.lock(); defer { lock.unlock() }; count += 1; return level }
}

/// A publish that changes nothing must not invalidate a view: the Home sliders are read every second while
/// the island is open, the now-playing card is fed from every activity layout, and none of it may redraw the
/// Home when the answer is the same. The poll itself must stop when the island closes.
@MainActor
@Suite(.serialized) struct HomeCoalescingTests {
    /// True when `mutate` invalidated what `read` touched.
    private func notifies(_ read: () -> Void, after mutate: () -> Void) -> Bool {
        let flag = Flag()
        withObservationTracking(read, onChange: { flag.set() })
        mutate()
        return flag.isSet
    }

    private func level(_ counter: LevelProbe, available: Bool = true) -> HomeLevel {
        HomeLevel(title: "Volume", systemImage: "speaker.wave.2.fill",
                  backend: LevelBackend(read: { available ? counter.read() : nil }, write: { _ in true }, unavailableReason: "x"))
    }

    @Test func rereadingTheSameLevelPublishesNothing() {
        let counter = LevelProbe()
        let level = level(counter)
        #expect(!notifies({ _ = level.value; _ = level.isAvailable }, after: { level.refresh() }))
    }

    @Test func aMovedLevelPublishesOnceAndAFlippedAvailabilityToo() {
        let counter = LevelProbe()
        let moved = level(counter)
        #expect(notifies({ _ = moved.value }, after: { counter.current = 0.8; moved.refresh() }))
        #expect(moved.value == 0.8)

        let gone = HomeLevel(title: "x", systemImage: "x", backend: LevelBackend(
            read: { counter.current > 0.9 ? nil : counter.read() }, write: { _ in true }, unavailableReason: "x"))
        counter.current = 0.5
        gone.refresh()
        #expect(gone.isAvailable)
        #expect(notifies({ _ = gone.isAvailable }, after: { counter.current = 0.95; gone.refresh() }))
        #expect(!gone.isAvailable)
    }

    @Test func settingTheSameLevelAgainPublishesNothing() {
        let counter = LevelProbe()
        let level = level(counter)
        #expect(!notifies({ _ = level.value }, after: { level.set(0.5) }))
        #expect(notifies({ _ = level.value }, after: { level.set(0.6) }))
    }

    @Test func assigningTheSameTrackPublishesNothingAndAChangedOneDoes() {
        let b = TestDefaults.make(); defer { b.cleanup() }
        let home = HomeModel(defaults: b.defaults)
        let track = HomeTrack(title: "A", artist: "B", isPlaying: true, progress: 0.25)
        home.track = track
        #expect(home.track == track)
        #expect(!notifies({ _ = home.track }, after: { home.track = HomeTrack(title: "A", artist: "B", isPlaying: true, progress: 0.25) }))
        #expect(notifies({ _ = home.track }, after: { home.track = HomeTrack(title: "A", artist: "B", isPlaying: true, progress: 0.5) }))
        #expect(notifies({ _ = home.track }, after: { home.track = nil }))
        #expect(!notifies({ _ = home.track }, after: { home.track = nil }))
    }

    // MARK: - The poll stops with the island

    private final class OffscreenHost {
        let window: NSWindow
        init<V: View>(_ view: V) {
            let host = NSHostingView(rootView: view)
            host.sizingOptions = []
            host.frame = NSRect(x: 0, y: 0, width: 640, height: 420)
            window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.alphaValue = 0
            window.contentView = host
            window.setFrameOrigin(CGPoint(x: -30_000, y: -30_000))
            window.orderFront(nil)
        }
        func close() { window.orderOut(nil) }
    }

    private func context(_ defaults: UserDefaults, volume: LevelProbe) -> ShellContext {
        let marker = CrashMarker(url: FileManager.default.temporaryDirectory.appendingPathComponent("mis-coalesce-\(UUID().uuidString)"))
        let registry = FeatureRegistry(descriptors: ShellDescriptors.all, defaults: defaults, crashMarker: marker)
        let table = QuickActionTable()
        for id in QuickAccessCatalog.defaultIDs { table.register(id) {} }
        let home = HomeModel(
            defaults: defaults,
            volume: LevelBackend(read: { volume.read() }, write: { _ in true }, unavailableReason: "x"),
            brightness: LevelBackend(read: { 0.5 }, write: { _ in true }, unavailableReason: "x"),
            keyboardLight: .unsupported("x"))
        return ShellContext(tabs: [], registry: registry, navigation: ShellNavigation(),
                            quickAccess: QuickAccessModel(defaults: defaults, table: table), home: home)
    }

    private func pump(_ seconds: TimeInterval) async {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            try? await Task.sleep(for: .milliseconds(10))
            RunLoop.current.run(until: Date().addingTimeInterval(0.002))
        }
    }

    @Test func aClosedIslandNeverPollsTheSystemLevels() async {
        let b = TestDefaults.make(); defer { b.cleanup() }
        let counter = LevelProbe()
        let context = context(b.defaults, volume: counter)
        let host = OffscreenHost(HomeIslandContent(context: context, notchWidth: 200, notchHeight: 32, isOpen: false, isLive: false))
        defer { host.close() }
        await pump(0.4)
        let settled = counter.reads
        await pump(2.4)  // more than two poll periods
        #expect(counter.reads == settled, "closed: \(counter.reads - settled) reads while closed")
    }

    @Test func anOpenIslandPollsAtMostOncePerSecondAndOffTheFirstFrames() async {
        let b = TestDefaults.make(); defer { b.cleanup() }
        let counter = LevelProbe()
        let context = context(b.defaults, volume: counter)
        let host = OffscreenHost(HomeIslandContent(context: context, notchWidth: 200, notchHeight: 32, isOpen: true, isLive: true))
        defer { host.close() }
        let atStart = counter.reads
        let began = Date()
        await pump(0.03)
        // (A process busy with other main-actor tests may have let more than 30 ms go by: only a read before
        // the poll's own 60 ms delay would be a bug, so look at the clock.)
        if Date().timeIntervalSince(began) < 0.055 {
            #expect(counter.reads == atStart, "nothing is read during the first frames of the open animation")
        }
        // Wait for the third read (the poll starts after 60 ms, then ticks every second), however long a busy
        // machine takes, then check the rate against the clock and not against a fixed window.
        while counter.reads - atStart < 3, Date().timeIntervalSince(began) < 12 { await pump(0.05) }
        let elapsed = Date().timeIntervalSince(began)
        let polls = counter.reads - atStart
        #expect(polls >= 3, "the poll runs while open (got \(polls) in \(elapsed) s)")
        #expect(Double(polls - 1) <= elapsed + 0.1, "and never faster than once a second (\(polls) reads in \(elapsed) s)")
    }
}
