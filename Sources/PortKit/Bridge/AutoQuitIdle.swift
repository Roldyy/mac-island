// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Lane W3D (auto-quit and Spaces). The lane owns this file.

import AppKit
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import os

// The inactivity half of auto-quit: an app that has had NO window for a set time is announced, then asked to
// quit when the countdown ends. It carries the logic of Mac Island's former Display module (the `display`
// feature), which the port replaced; the keys it reads are the ones that module already used
// (`autoQuitDelayMinutes`, `autoQuitDryRun`), so nothing a person set is lost. The other half, "quit after the
// last window closes", is the upstream service (`AutoQuitService`).
//
// Both halves obey `AutoQuitSafety`, share the one never-quit list (`DefaultsKey.autoQuitExceptions`) and end an
// app only with the polite `terminate()`.

// MARK: - Keys

enum AutoQuitIdleKeys {
    /// New switch of this half: off until the person turns it on. (`autoQuitEnabled` is the upstream last-window
    /// switch now; `settleLegacyEnabledFlag` moves an old stored value so nobody gets the last-window behaviour
    /// they never asked for.)
    static let enabled = "autoQuitIdleEnabled"
    static let delayMinutes = "autoQuitDelayMinutes"
    static let dryRun = "autoQuitDryRun"
    /// The old module's own exclusion list, folded once into `DefaultsKey.autoQuitExceptions`.
    static let legacyExclusions = "autoQuitExcludedBundleIDs"
    static let legacyAdoptedKey = "migration.autoquit.exclusionsAdopted.done"

    static let defaultDelayMinutes = 30
    static let maxDelayMinutes = 24 * 60

    static func delay(in defaults: UserDefaults) -> Int {
        guard let n = (defaults.object(forKey: delayMinutes) as? NSNumber)?.intValue else { return defaultDelayMinutes }
        return min(maxDelayMinutes, max(1, n))
    }

    /// Absent means dry run: the first real quit needs an explicit choice.
    static func isDryRun(in defaults: UserDefaults) -> Bool {
        (defaults.object(forKey: dryRun) as? Bool) ?? true
    }

    static let legacyFlagSettledKey = "migration.autoquit.enabledFlagSettled.done"
    /// True when the settle below switched a stored `autoQuitEnabled` off: the page says so next to the toggle.
    static let lastWindowResetKey = "migration.autoquit.lastWindowReset"

    /// The old module's own keys: any of them set means `autoQuitEnabled` was written by it (a Vorssaint page never
    /// writes these).
    static func hasLegacyIdleSettings(in defaults: UserDefaults) -> Bool {
        [delayMinutes, dryRun, legacyExclusions].contains { defaults.object(forKey: $0) != nil }
    }

    /// Once, at bind (before the person can touch the page, before any start): `autoQuitEnabled` is upstream's
    /// "quit when the last window closes" switch now, but our retired Display module stored its IDLE switch under
    /// that very name. A stored `true` is therefore never left to turn the last-window behaviour on by itself:
    /// - written by our old module (one of its own keys is set): its choice moves to `autoQuitIdleEnabled`
    ///   (unless that one was already chosen) and the last-window key goes off;
    /// - otherwise (it cannot be told apart): the last-window key goes off too, and stays off until the person
    ///   switches it on in the page, which shows the real state and a note.
    /// A stored `false` or an absent key is left alone.
    static func settleLegacyEnabledFlag(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: legacyFlagSettledKey) else { return }
        defaults.set(true, forKey: legacyFlagSettledKey)
        guard (defaults.object(forKey: DefaultsKey.autoQuitEnabled) as? Bool) == true else { return }
        if hasLegacyIdleSettings(in: defaults), defaults.object(forKey: enabled) == nil {
            defaults.set(true, forKey: enabled)
        }
        defaults.set(false, forKey: DefaultsKey.autoQuitEnabled)
        defaults.set(true, forKey: lastWindowResetKey)
    }

    /// Once: the old module's exclusions join the shared never-quit list. Nothing is removed. Also settles the
    /// legacy `autoQuitEnabled` flag (above), so the lane's one bind-time call covers both.
    static func adoptLegacyExclusions(in defaults: UserDefaults) {
        settleLegacyEnabledFlag(in: defaults)  // same one-shot, run at bind
        guard !defaults.bool(forKey: legacyAdoptedKey) else { return }
        defaults.set(true, forKey: legacyAdoptedKey)
        let legacy = defaults.stringArray(forKey: legacyExclusions) ?? []
        guard !legacy.isEmpty else { return }
        let current = defaults.stringArray(forKey: DefaultsKey.autoQuitExceptions) ?? []
        defaults.set(Defaults.sanitizedAutoQuitExceptions(current + legacy), forKey: DefaultsKey.autoQuitExceptions)
    }
}

// MARK: - Facts about running apps

/// One running app at scan time. `name` is for the page only and is never logged.
struct AutoQuitAppSnapshot: Equatable, Sendable {
    var pid: Int32
    var bundleID: String?
    var name: String
    /// `NSApplication.ActivationPolicy.regular`: a Dock app. Agents and accessories are false.
    var isRegular: Bool
    var isFrontmost: Bool
    var isPlayingAudio: Bool
    /// Layer-0 windows owned by the app, whatever their state (minimized and other-Space ones count).
    var windowCount: Int
    /// Hidden with Cmd+H: its windows are off screen but the app is in use.
    var isHidden: Bool = false
}

/// One CoreAudio process object that has output running.
struct AutoQuitPlayingProcess: Equatable {
    var pid: Int32
    var bundleID: String?
}

/// Which apps are making sound. A browser plays through helper processes with their own pid, so a process is
/// attributed to the app that owns it (same pid, a parent in the pid tree, or an app bundle id that prefixes the
/// helper's own).
enum AutoQuitAudio {
    struct Attribution: Equatable {
        /// Pids of apps (from `apps`) that own at least one process running output.
        var appPIDs: Set<Int32> = []
        /// A process runs output that no known app owns (a system service such as a web engine's audio process):
        /// the caller must then assume any app may be the source.
        var hasUnattributed = false
    }

    static let maxDepth = 32

    static func attribute(playing: [AutoQuitPlayingProcess], apps: [Int32: String],
                          knownPIDs: Set<Int32>, parentOf: (Int32) -> Int32?) -> Attribution {
        var result = Attribution()
        for process in playing {
            if let owner = owner(of: process, apps: apps, parentOf: parentOf) {
                result.appPIDs.insert(owner)
            } else if !knownPIDs.contains(process.pid) {
                result.hasUnattributed = true
            }
        }
        return result
    }

    private static func owner(of process: AutoQuitPlayingProcess, apps: [Int32: String],
                              parentOf: (Int32) -> Int32?) -> Int32? {
        if apps[process.pid] != nil { return process.pid }
        var seen: Set<Int32> = [process.pid]
        var current = process.pid
        for _ in 0..<maxDepth {
            guard let parent = parentOf(current), parent > 1, seen.insert(parent).inserted else { break }
            if apps[parent] != nil { return parent }
            current = parent
        }
        guard let bundle = process.bundleID, !bundle.isEmpty else { return nil }
        // Longest bundle id that prefixes the helper's at a dot boundary.
        return apps.filter { bundle.hasPrefix($0.value + ".") }
            .max { $0.value.count < $1.value.count }?.key
    }

    /// True when the app at `pid` (or one of its helpers) has output running, or when some sound has no known
    /// owner (then any app may be the source: the answer errs toward keeping the app).
    static func isPlaying(pid: Int32) -> Bool {
        let running = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        var byPID: [Int32: String] = [:]
        for app in running where app.activationPolicy == .regular {
            if let bundle = app.bundleIdentifier { byPID[app.processIdentifier] = bundle }
        }
        let attribution = attribute(playing: playingProcesses(), apps: byPID,
                                    knownPIDs: Set(running.map(\.processIdentifier)), parentOf: parentPID(of:))
        return attribution.appPIDs.contains(pid) || attribution.hasUnattributed
    }

    static func playingProcesses() -> [AutoQuitPlayingProcess] {
        guard #available(macOS 14.2, *) else { return [] }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }

        var found: [AutoQuitPlayingProcess] = []
        for object in objects {
            var running: UInt32 = 0
            var runSize = UInt32(MemoryLayout<UInt32>.size)
            var runAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningOutput,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(object, &runAddress, 0, nil, &runSize, &running) == noErr,
                  running != 0 else { continue }
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            var pidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(object, &pidAddress, 0, nil, &pidSize, &pid) == noErr else { continue }
            var bundle: String?
            var bundleAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyBundleID,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var cf: Unmanaged<CFString>?
            var cfSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let status = withUnsafeMutablePointer(to: &cf) {
                AudioObjectGetPropertyData(object, &bundleAddress, 0, nil, &cfSize, $0)
            }
            if status == noErr, let cf { bundle = cf.takeRetainedValue() as String }
            found.append(AutoQuitPlayingProcess(pid: pid, bundleID: bundle))
        }
        return found
    }

    /// Parent pid through `proc_pidinfo`; nil when the process is gone or unreadable.
    static func parentPID(of pid: Int32) -> Int32? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Int32(bitPattern: info.pbi_ppid)
    }
}

/// Counts layer-0 windows per owner pid, in any state: minimized, on another Space, full screen elsewhere and
/// windows of a hidden app all count. "On screen only" would make those apps look windowless. Needs no Screen
/// Recording permission (window titles are never read).
enum AutoQuitWindowCounter {
    static let minimumSide: Double = 8

    typealias WindowLister = (CGWindowListOption, CGWindowID) -> [[String: Any]]

    static let systemLister: WindowLister = { options, relativeTo in
        (CGWindowListCopyWindowInfo(options, relativeTo) as? [[String: Any]]) ?? []
    }

    static func currentCounts(lister: WindowLister = systemLister) -> [Int32: Int] {
        counts(from: lister([.optionAll, .excludeDesktopElements], kCGNullWindowID))
    }

    static func counts(from windows: [[String: Any]]) -> [Int32: Int] {
        var result: [Int32: Int] = [:]
        for window in windows {
            guard let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  ((window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0.01,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let w = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let h = (bounds["Height"] as? NSNumber)?.doubleValue,
                  w >= minimumSide, h >= minimumSide else { continue }
            result[pid, default: 0] += 1
        }
        return result
    }
}

// MARK: - Policy (pure)

struct AutoQuitIdleConfig: Equatable {
    var delay: TimeInterval
    var neverQuit: Set<String>
    var ownPID: Int32
    var ownBundleIDs: Set<String>
}

/// Which apps have been idle long enough. No clock, no system calls.
enum AutoQuitIdlePlanner {
    static func candidates(apps: [AutoQuitAppSnapshot], lastActive: [Int32: Date], now: Date,
                           monitoringSince: Date, config: AutoQuitIdleConfig) -> [AutoQuitAppSnapshot] {
        // Never act before one full interval of observation, whatever the tracker says.
        guard now.timeIntervalSince(monitoringSince) >= config.delay else { return [] }
        return apps.filter { app in
            guard !app.isHidden, app.windowCount == 0, let last = lastActive[app.pid] else { return false }
            let veto = AutoQuitSafety.veto(
                pid: app.pid, bundleID: app.bundleID, isRegular: app.isRegular, path: .inactivity,
                ownPID: config.ownPID, ownBundleIDs: config.ownBundleIDs, neverQuit: config.neverQuit,
                isFrontmost: app.isFrontmost, isPlayingAudio: app.isPlayingAudio, hasOpenPanel: false)
            return veto == nil && now.timeIntervalSince(last) >= config.delay
        }
        .sorted { $0.pid < $1.pid }
    }
}

/// Remembers, per pid, the last time an app was seen busy (window, frontmost or audio). First sighting counts as
/// active, so a fresh launch never inherits an old idle time.
struct AutoQuitIdleTracker: Equatable {
    private(set) var lastActive: [Int32: Date] = [:]

    mutating func update(_ apps: [AutoQuitAppSnapshot], now: Date) {
        var next: [Int32: Date] = [:]
        for app in apps {
            if app.windowCount > 0 || app.isFrontmost || app.isPlayingAudio {
                next[app.pid] = now
            } else {
                next[app.pid] = lastActive[app.pid] ?? now
            }
        }
        lastActive = next
    }

    mutating func reset() { lastActive = [:] }
}

struct AutoQuitPendingQuit: Equatable, Identifiable {
    var pid: Int32
    var bundleID: String?
    var name: String
    var deadline: Date
    var id: Int32 { pid }
}

/// Planner plus the announce-then-act countdown. Pure: the caller supplies time and snapshots and performs the
/// terminations it is told about.
struct AutoQuitIdleEngine {
    struct Output: Equatable {
        var pending: [AutoQuitPendingQuit] = []
        var terminate: [Int32] = []
    }

    var countdown: TimeInterval = 60
    private var tracker = AutoQuitIdleTracker()
    private var monitoringSince: Date?
    private var pending: [Int32: AutoQuitPendingQuit] = [:]
    private var attempted: Set<Int32> = []

    init(countdown: TimeInterval = 60) { self.countdown = countdown }

    mutating func reset() {
        tracker.reset()
        monitoringSince = nil
        pending = [:]
        attempted = []
    }

    mutating func tick(apps: [AutoQuitAppSnapshot], now: Date, config: AutoQuitIdleConfig,
                       enabled: Bool, dryRun: Bool) -> Output {
        guard enabled else {
            reset()
            return Output()
        }
        if monitoringSince == nil { monitoringSince = now }
        tracker.update(apps, now: now)
        attempted.formIntersection(Set(apps.map(\.pid)))

        let candidates = AutoQuitIdlePlanner.candidates(
            apps: apps, lastActive: tracker.lastActive, now: now,
            monitoringSince: monitoringSince ?? now, config: config
        ).filter { !attempted.contains($0.pid) }

        var next: [Int32: AutoQuitPendingQuit] = [:]
        for app in candidates {
            next[app.pid] = pending[app.pid] ?? AutoQuitPendingQuit(
                pid: app.pid, bundleID: app.bundleID, name: app.name,
                deadline: now.addingTimeInterval(countdown))
        }
        pending = next

        var output = Output()
        if !dryRun {
            let due = next.values.filter { $0.deadline <= now }.map(\.pid).sorted()
            for pid in due {
                pending[pid] = nil
                attempted.insert(pid)
            }
            output.terminate = due
        }
        output.pending = pending.values.sorted { $0.pid < $1.pid }
        return output
    }
}

// MARK: - System touch points

protocol AutoQuitIdleScanning {
    @MainActor func snapshot() -> [AutoQuitAppSnapshot]
}

protocol AutoQuitTerminating {
    /// Polite `terminate()` only: the app may show a save prompt and refuse. Never a forced quit.
    @MainActor func terminate(pid: Int32) -> Bool
}

struct AutoQuitWorkspaceScanner: AutoQuitIdleScanning {
    @MainActor func snapshot() -> [AutoQuitAppSnapshot] {
        let counts = AutoQuitWindowCounter.currentCounts()
        let running = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }
        var byPID: [Int32: String] = [:]
        for app in running where app.activationPolicy == .regular {
            if let bundle = app.bundleIdentifier { byPID[app.processIdentifier] = bundle }
        }
        let audio = AutoQuitAudio.attribute(
            playing: AutoQuitAudio.playingProcesses(), apps: byPID,
            knownPIDs: Set(running.map(\.processIdentifier)), parentOf: AutoQuitAudio.parentPID(of:))
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return running.map { app in
            let pid = app.processIdentifier
            return AutoQuitAppSnapshot(
                pid: pid, bundleID: app.bundleIdentifier,
                name: app.localizedName ?? app.bundleIdentifier ?? "?",
                isRegular: app.activationPolicy == .regular,
                isFrontmost: pid == frontPID || app.isActive,
                // A process playing sound that no app owns (a system web-engine service) could be any app's:
                // keep them all this scan rather than quit the one that is playing.
                isPlayingAudio: audio.appPIDs.contains(pid) || audio.hasUnattributed,
                windowCount: counts[pid] ?? 0,
                isHidden: app.isHidden)
        }
    }
}

struct AutoQuitWorkspaceTerminator: AutoQuitTerminating {
    @MainActor func terminate(pid: Int32) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.terminate() ?? false
    }
}

// MARK: - Monitor

/// Drives the inactivity scan loop and holds what the Settings page shows. Started and stopped by the lane:
/// `sync()` runs only while the feature is available (the registry let it run) AND the person turned the half on.
@MainActor
final class AutoQuitIdleMonitor: ObservableObject {
    static let shared = AutoQuitIdleMonitor()
    static let scanInterval: TimeInterval = 15
    private static let log = Logger(subsystem: "be.roldy.macisland", category: "autoquit")

    @Published private(set) var pending: [AutoQuitPendingQuit] = []

    private var engine = AutoQuitIdleEngine()
    private let defaults: () -> UserDefaults
    private let isAvailable: () -> Bool
    private let hasAccessibility: () -> Bool
    private let scanner: AutoQuitIdleScanning
    private let terminator: AutoQuitTerminating
    private let gate: AutoQuitGate
    private let clock: () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void
    private var loop: Task<Void, Never>?

    init(defaults: @escaping () -> UserDefaults = { PortHost.defaults },
         isAvailable: @escaping () -> Bool = { AppFeature.autoQuit.isAvailable },
         hasAccessibility: @escaping () -> Bool = { Permissions.shared.accessibility },
         scanner: AutoQuitIdleScanning = AutoQuitWorkspaceScanner(),
         terminator: AutoQuitTerminating = AutoQuitWorkspaceTerminator(),
         gate: AutoQuitGate = .live,
         clock: @escaping () -> Date = Date.init,
         sleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
             try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
         }) {
        self.defaults = defaults
        self.isAvailable = isAvailable
        self.hasAccessibility = hasAccessibility
        self.scanner = scanner
        self.terminator = terminator
        self.gate = gate
        self.clock = clock
        self.sleep = sleep
    }

    var isRunning: Bool { loop != nil }

    /// Follows the registry's verdict and the page toggle. Idempotent.
    func sync() {
        if isWanted { start() } else { stop() }
    }

    /// The registry lets the feature run, Accessibility is granted (the feature's permission, same as the other
    /// half) and the person turned this half on.
    private var isWanted: Bool {
        isAvailable() && hasAccessibility() && defaults().bool(forKey: AutoQuitIdleKeys.enabled)
    }

    private func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
                await self.sleep(Self.scanInterval)
            }
        }
    }

    /// Idempotent. Stopping forgets the idle clocks: the next start waits a full interval again.
    func stop() {
        loop?.cancel()
        loop = nil
        engine.reset()
        pending = []
    }

    func tick() {
        let store = defaults()
        let enabled = isWanted
        let apps = enabled ? scanner.snapshot() : []
        let neverQuit = Set(Defaults.sanitizedAutoQuitExceptions(store.stringArray(forKey: DefaultsKey.autoQuitExceptions) ?? []))
        let config = AutoQuitIdleConfig(
            delay: TimeInterval(AutoQuitIdleKeys.delay(in: store)) * 60, neverQuit: neverQuit,
            ownPID: gate.environment.ownPID(), ownBundleIDs: gate.environment.ownBundleIDs())
        let output = engine.tick(apps: apps, now: clock(), config: config, enabled: enabled,
                                 dryRun: AutoQuitIdleKeys.isDryRun(in: store))
        pending = output.pending
        var asked = 0
        for pid in output.terminate {
            // The last look, live, right before the only call that ends an app: a panel may have opened, the app
            // may have come to the front or started playing since the scan.
            let bundleID = apps.first { $0.pid == pid }?.bundleID
            guard gate.veto(pid: pid, bundleID: bundleID, path: .inactivity) == nil else { continue }
            if terminator.terminate(pid: pid) { asked += 1 }
        }
        if !output.pending.isEmpty || !output.terminate.isEmpty {
            Self.log.info("scan: \(apps.count) apps, \(output.pending.count) announced, \(output.terminate.count) due, \(asked) asked to quit")
        }
    }
}
