// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Status chips bridge (MIS_0102). Hand-written, never touched by import.sh.

import AppKit
import Foundation
import ShellKit

/// What the chip needs to know about a running app to decide whether Quit is allowed.
struct TopAppRunningInfo: Equatable, Sendable {
    var bundleID: String?
    /// A regular (Dock) app: the only kind the chip offers to quit.
    var isRegularApp: Bool
}

/// Pure part of the "Appli gourmande" chip.
enum TopAppChip {
    typealias Level = StatusChipReading.Level
    static let nameLimit = 20

    /// Judged on the value the chip shows (whole percent): attention from 60, alert from 90.
    static func level(percent: Double) -> Level {
        guard percent.isFinite else { return .normal }
        let shown = Int(percent.rounded())
        return shown >= 90 ? .alert : shown >= 60 ? .attention : .normal
    }

    /// "Safari 42 % CPU".
    static func primary(name: String, percent: Double) -> String {
        let shown = Int(min(max(percent.isFinite ? percent : 0, 0), 999).rounded())
        let label = StatusChipBridgeFormat.truncated(name, limit: nameLimit)
        return "\(label.isEmpty ? "Appli" : label) \(shown) % CPU"
    }

    /// The reading for the busiest app. `quit` is nil when Quit is not allowed: no action at all then (the chip is
    /// not tappable). When it is allowed, the action is destructive, so the row asks for a second click.
    static func reading(name: String, percent: Double, quit: (@MainActor () -> Void)?) -> StatusChipReading {
        var actions: [StatusChipAction] = []
        if let quit {
            actions.append(StatusChipAction(id: "quit", title: "Quitter", systemImage: "xmark.circle",
                                            isDestructive: true, handler: quit))
        }
        return StatusChipReading(kind: .topApp, primary: primary(name: name, percent: percent),
                                 level: level(percent: percent), actions: actions)
    }
}

/// "Appli gourmande": the app using the most processor, from `ProcessUsageService`, every 3 s while the island is
/// open (the libproc sweep runs off the main thread; the service keeps its own two-sample delta, so the first tick of
/// a run has no reading).
///
/// Quit is offered only when every condition holds: the process is not on the refusal list (`TopAppQuitPolicy`),
/// not protected by `KillProcessService`, a regular app, the Kill Process feature is on and the row carries the
/// kernel start time that `KillProcessService.kill(pid:name:startedAt:force:)` uses to be sure the pid still
/// is the same process. The kill is never forced: `NSRunningApplication.terminate()` for an app.
@MainActor
final class TopAppChipSource: StatusChipBridgeSource {
    nonisolated static let interval: Duration = .seconds(3)

    struct Hooks {
        var read: @Sendable () -> [ProcessUsage]
        var appInfo: @MainActor (pid_t) -> TopAppRunningInfo?
        var ownPID: Int32
        var ownBundleID: String?
        var canKill: @MainActor () -> Bool
        var isProtected: @MainActor (pid_t, String) -> Bool
        var quit: @MainActor (pid_t, String, UInt64) -> Void
        var sleep: @Sendable (Duration) async throws -> Void

        @MainActor static var live: Hooks {
            Hooks(
                read: { ProcessUsageService.shared.topCPU(limit: 1, sampleInterval: 3) },
                appInfo: { pid in
                    NSRunningApplication(processIdentifier: pid).map {
                        TopAppRunningInfo(bundleID: $0.bundleIdentifier, isRegularApp: $0.activationPolicy == .regular)
                    }
                },
                ownPID: getpid(),
                ownBundleID: Bundle.main.bundleIdentifier,
                canKill: { AppFeature.killProcess.isAvailable },
                isProtected: { KillProcessService.isProtected(pid: $0, name: $1) },
                quit: { pid, name, startedAt in
                    KillProcessService.shared.kill(pid: pid, name: name, startedAt: startedAt, force: false)
                },
                sleep: StatusChipBridgeSource.sleeper(tolerance: .milliseconds(500)))
        }
    }

    private let interval: Duration
    private let hooks: Hooks
    private var poller: Task<Void, Never>?

    init(interval: Duration = TopAppChipSource.interval, hooks: Hooks? = nil) {
        self.interval = interval
        self.hooks = hooks ?? .live
        super.init(kind: .topApp)
    }

    override func begin() {
        poller = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let read = self.hooks.read
                let rows = await Task.detached(priority: .utility) { read() }.value
                guard !Task.isCancelled else { return }
                self.apply(rows)
                do { try await self.hooks.sleep(self.interval) } catch { return }
            }
        }
    }

    override func end() {
        poller?.cancel()
        poller = nil
    }

    /// Builds and publishes the reading for the busiest row (nil for no row).
    func apply(_ rows: [ProcessUsage]) {
        guard let top = rows.max(by: { $0.value < $1.value }) else { publish(nil); return }
        var quit: (@MainActor () -> Void)?
        if canQuit(top), let startedAt = top.startedAt {
            let (pid, name, hooks) = (top.pid, top.name, hooks)
            quit = { hooks.quit(pid, name, startedAt) }
        }
        publish(TopAppChip.reading(name: top.name, percent: top.value, quit: quit))
    }

    /// Every condition of the Quit action except the start time (checked by the caller).
    func canQuit(_ row: ProcessUsage) -> Bool {
        guard hooks.canKill(), !hooks.isProtected(row.pid, row.name),
              let info = hooks.appInfo(row.pid), info.isRegularApp else { return false }
        return !TopAppQuitPolicy.isRefused(name: row.name, bundleID: info.bundleID, pid: row.pid,
                                           ownPID: hooks.ownPID, ownBundleID: hooks.ownBundleID)
    }
}
