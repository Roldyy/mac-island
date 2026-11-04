// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Status chips bridge (MIS_0102). Hand-written, never touched by import.sh.

import Foundation
import ShellKit

/// What the battery chip needs from a `PowerReading`: plain values, so the chip is testable without a battery.
struct BatteryHealthSample: Equatable, Sendable {
    var healthPercent: Double?
    var cycleCount: Int?
    var timeRemaining: TimeInterval?
    var externalConnected: Bool

    init(healthPercent: Double? = nil, cycleCount: Int? = nil, timeRemaining: TimeInterval? = nil,
         externalConnected: Bool = false) {
        self.healthPercent = healthPercent
        self.cycleCount = cycleCount
        self.timeRemaining = timeRemaining
        self.externalConnected = externalConnected
    }
}

/// Thresholds and text of the battery chip. Pure.
enum BatteryHealthChip {
    typealias Level = StatusChipReading.Level

    /// Judged on the value the chip shows (whole percent): attention under 80, alert under 70.
    static func level(health: Double) -> Level {
        guard health.isFinite else { return .normal }
        let shown = Int(health.rounded())
        return shown < 70 ? .alert : shown < 80 ? .attention : .normal
    }

    /// "92 % santé" then "312 cycles · 3 h 20 min" or "312 cycles · branchée". Nil when neither the health nor the
    /// cycle count is known (nothing worth a chip).
    static func reading(_ sample: BatteryHealthSample, openMonitor: (@MainActor () -> Void)?) -> StatusChipReading? {
        var parts: [String] = []
        if let cycles = sample.cycleCount { parts.append(StatusChipBridgeFormat.cycles(cycles)) }
        if sample.externalConnected {
            parts.append("branchée")
        } else if let remaining = sample.timeRemaining, remaining > 0 {
            parts.append(StatusChipBridgeFormat.duration(remaining))
        } else {
            parts.append("sur batterie")
        }
        let primary: String
        let level: Level
        if let health = sample.healthPercent, health.isFinite {
            primary = "\(Int(min(max(health, 0), 100).rounded())) % santé"
            level = self.level(health: health)
        } else if let cycles = sample.cycleCount {
            primary = StatusChipBridgeFormat.cycles(cycles)
            parts.removeFirst()
            level = .normal
        } else {
            return nil
        }
        var actions: [StatusChipAction] = []
        if let openMonitor {
            actions.append(StatusChipAction(id: "monitor", title: "Ouvrir le Moniteur",
                                            systemImage: "chart.line.uptrend.xyaxis", handler: openMonitor))
        }
        return StatusChipReading(kind: .batteryHealth, primary: primary,
                                 secondary: parts.isEmpty ? nil : parts.joined(separator: " · "),
                                 level: level, actions: actions)
    }
}

/// "Batterie": health, cycles and time left, read from `PowerSampler` every 60 s while the island is open.
///
/// `PowerSampler.sample()` reads the battery's registry entry (milliseconds) and takes the exact "maximum capacity"
/// from `MaxCapacityProbe`, which caches it for 30 minutes process-wide: `system_profiler` is never spawned by a
/// tick of this chip. The sampler is built without an SMC client, so no SMC key is read either. A Mac without an
/// internal battery gives no reading, so no chip.
@MainActor
final class BatteryHealthChipSource: StatusChipBridgeSource {
    nonisolated static let interval: Duration = .seconds(60)

    private let interval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let read: @MainActor () -> BatteryHealthSample?
    private let navigator: StatusChipNavigator
    private var poller: Task<Void, Never>?

    init(interval: Duration = BatteryHealthChipSource.interval,
         sleep: @escaping @Sendable (Duration) async throws -> Void = StatusChipBridgeSource.sleeper(tolerance: .seconds(10)),
         navigator: StatusChipNavigator? = nil,
         read: (@MainActor () -> BatteryHealthSample?)? = nil) {
        self.interval = interval
        self.sleep = sleep
        self.navigator = navigator ?? .live
        self.read = read ?? Self.liveReader()
        super.init(kind: .batteryHealth)
    }

    /// One `PowerSampler` for the life of the source (its battery service handle is reused between ticks).
    private static func liveReader() -> @MainActor () -> BatteryHealthSample? {
        let sampler = PowerSampler(smc: nil)
        return {
            guard PowerSampler.hasInternalBattery else { return nil }
            let power = sampler.sample()
            guard power.hasBattery else { return nil }
            return BatteryHealthSample(healthPercent: power.healthPercent, cycleCount: power.cycleCount,
                                       timeRemaining: power.timeRemainingSeconds,
                                       externalConnected: power.externalConnected)
        }
    }

    override func begin() {
        refresh()
        poller = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do { try await self.sleep(self.interval) } catch { return }
                guard !Task.isCancelled else { return }
                self.refresh()
            }
        }
    }

    override func end() {
        poller?.cancel()
        poller = nil
    }

    func refresh() {
        guard let sample = read() else { publish(nil); return }
        let navigator = navigator
        var openMonitor: (@MainActor () -> Void)?
        if navigator.isAvailable() { openMonitor = { navigator.open("monitor") } }
        publish(BatteryHealthChip.reading(sample, openMonitor: openMonitor))
    }
}
