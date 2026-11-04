// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Status chips bridge (MIS_0102). Hand-written, never touched by import.sh.

import Combine
import Foundation
import ShellKit

/// Who asks `SystemMonitor` for the peripheral batteries. The monitor has one boolean for the island's accessory
/// consumer (`setNotchAccessoryMonitoring`), owned by `NotchAccessoryService` while the Accessories feature is on:
/// the chip must neither set it nor clear it in that case.
struct AccessoryMonitorControl {
    /// True while another owner (the Accessories feature) holds the flag.
    var isOwnedElsewhere: @MainActor () -> Bool
    var setMonitoring: @MainActor (Bool) -> Void

    @MainActor static let live = AccessoryMonitorControl(
        isOwnedElsewhere: { NotchAccessorySupport.isEnabled() },
        setMonitoring: { SystemMonitor.shared.setNotchAccessoryMonitoring($0) })
}

/// Pure part of the "Appareils" chip.
enum DevicesChip {
    typealias Level = StatusChipReading.Level

    /// A sample read longer ago than this (system uptime, seconds) is a leftover of an earlier run: Bluetooth levels
    /// are cached for 5 minutes by the sampler, twice that is the longest a live value can be.
    static let maxAge: TimeInterval = 600
    static let nameLimit = 20

    /// Devices with a plausible level read recently, lowest battery first (ties by name, then id).
    static func ordered(_ sample: PeripheralBatterySample, now: TimeInterval) -> [PeripheralBatteryDevice] {
        sample.devices
            .filter { device in
                (0...100).contains(device.percent) && sample.observedAt[device.id].map { now - $0 <= maxAge } == true
            }
            .sorted {
                if $0.percent != $1.percent { return $0.percent < $1.percent }
                if $0.name != $1.name { return $0.name < $1.name }
                return $0.id < $1.id
            }
    }

    /// Attention at 20 % or less, alert at 10 % or less.
    static func level(percent: Int) -> Level { percent <= 10 ? .alert : percent <= 20 ? .attention : .normal }

    /// "AirPods Pro 80 %" then "+2 autres"; nil without a device. Read-only: no action.
    static func reading(_ devices: [PeripheralBatteryDevice]) -> StatusChipReading? {
        guard let lowest = devices.first else { return nil }
        let name = StatusChipBridgeFormat.truncated(lowest.name, limit: nameLimit)
        return StatusChipReading(
            kind: .devices, primary: "\(name.isEmpty ? "Appareil" : name) \(lowest.percent) %",
            secondary: devices.count > 1 ? StatusChipBridgeFormat.others(devices.count - 1) : nil,
            symbol: NotchAccessorySupport.symbol(for: lowest.kind, name: lowest.name),
            level: level(percent: lowest.percent))
    }
}

/// "Appareils": the battery of the connected Bluetooth devices, from `SystemMonitor`'s peripheral sampler.
///
/// Between `start()` and `stop()` the chip observes the monitor's snapshot and, unless the Accessories feature already
/// owns the monitor's accessory flag, sets that flag on and clears it again at `stop()`. It reads no hardware itself
/// and has no timer: the sampler's own 15 s stride (5 min for Bluetooth) drives the updates.
@MainActor
final class DevicesChipSource: StatusChipBridgeSource {
    struct Hooks {
        /// Calls `deliver` with the monitor's peripheral sample each time it changes (and once when subscribed).
        var watch: @MainActor (_ deliver: @escaping @MainActor (PeripheralBatterySample) -> Void) -> AnyCancellable?
        var uptime: @MainActor () -> TimeInterval

        @MainActor static let live = Hooks(
            watch: { deliver in
                SystemMonitor.shared.$snapshot.map(\.peripheralBatterySample).removeDuplicates()
                    .receive(on: DispatchQueue.main)
                    .sink { sample in MainActor.assumeIsolated { deliver(sample) } }
            },
            uptime: { ProcessInfo.processInfo.systemUptime })
    }

    private let hooks: Hooks
    private let monitor: AccessoryMonitorControl
    private var subscription: AnyCancellable?
    /// True when this chip turned the monitor's accessory flag on and so owes its release.
    private(set) var ownsMonitoring = false

    init(hooks: Hooks? = nil, monitor: AccessoryMonitorControl? = nil) {
        self.hooks = hooks ?? .live
        self.monitor = monitor ?? .live
        super.init(kind: .devices)
    }

    override func begin() {
        if !monitor.isOwnedElsewhere() {
            ownsMonitoring = true
            monitor.setMonitoring(true)
        }
        subscription = hooks.watch { [weak self] sample in
            guard let self, self.isRunning else { return }
            self.publish(DevicesChip.reading(DevicesChip.ordered(sample, now: self.hooks.uptime())))
        }
    }

    override func end() {
        subscription = nil
        guard ownsMonitoring else { return }
        ownsMonitoring = false
        // The Accessories feature may have been switched on meanwhile: it then owns the flag and keeps it.
        if !monitor.isOwnedElsewhere() { monitor.setMonitoring(false) }
    }
}
