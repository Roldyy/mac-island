// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Status chips bridge (MIS_0102). Hand-written, never touched by import.sh.

import Foundation
import ShellKit

/// The one public door of the status-chip bridge: the chips that need PortKit's services (battery health, next
/// appointment, busiest app, Bluetooth devices, timer) and the processor temperature of the "Charge" chip.
/// PortKit's types are internal, so `AppDelegate` plugs these two functions into `ShellContext.statusSources` and
/// `ShellContext.statusTemperature`.
///
/// Nothing here samples until the feed calls `start()` on a source (the island is open and the chip is on); each
/// source stops every task and listener at `stop()`.
public enum PortStatusChips {
    /// One fresh source per chip kind: `batteryHealth`, `nextEvent`, `topApp`, `devices`, `timer`.
    @MainActor public static func sources() -> [any StatusChipSource] {
        [BatteryHealthChipSource(), NextEventChipSource(), TopAppChipSource(), DevicesChipSource(), TimerChipSource()]
    }

    /// The CPU temperature in degrees Celsius, nil until known or when the sensor is unreadable. Meant to be called
    /// by the Load chip only (see `CPUTemperatureLease`).
    @MainActor public static func temperature() -> Double? {
        CPUTemperatureLease.shared.temperature()
    }

    /// Gives back the monitor reference `temperature()` took. Called when the Load chip stops (the island closed).
    @MainActor public static func releaseTemperature() {
        CPUTemperatureLease.shared.release()
    }
}
