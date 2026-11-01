// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management

import Combine
import Foundation
import IslandKit

/// What the system answered for the permissions the ported tap features use, at one moment. Mirrors ShellKit's
/// `PermissionSnapshot` (PortKit cannot see ShellKit): the app delegate copies every reading of the
/// `PermissionMonitor` here, and nothing in PortKit reads the system for these three itself.
public struct PortPermissionState: Equatable, Sendable {
    public var accessibility: Bool
    public var inputMonitoring: Bool
    public var screenRecording: Bool

    public init(accessibility: Bool = false, inputMonitoring: Bool = false, screenRecording: Bool = false) {
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
        self.screenRecording = screenRecording
    }
}

/// The host's state the ported code reads. Everything is nil or off until the app delegate fills it, so
/// importing PortKit (or running its tests) starts, writes and asks for nothing.
extension PortHost {
    /// The defaults object of the whole port. The registry and the migrator use `AppDefaults.make()`: in the app
    /// bundle that is `.standard`, under `swift run` and in tests it is the `be.roldy.macisland` suite, so the
    /// ported code must use it too or it would read another domain than the one the migrator filled. The app
    /// delegate sets it once at launch; tests set a temporary suite.
    public nonisolated(unsafe) static var defaults: UserDefaults = AppDefaults.make() ?? .standard

    /// Whether the registry lets a ported feature run: nil for an id no binding owns (the ported code then reads
    /// the stored switch, as upstream did). Set by `PortFeatureBinding`; read by `AppFeature.isAvailable`.
    public nonisolated(unsafe) static var availability: (@Sendable (_ registryID: String) -> Bool?)?

    /// The `shell.enabled.<id>` value the registry holds, nil when the user never chose it. For the upstream
    /// first-launch seeds that read an availability switch.
    public nonisolated(unsafe) static var storedSwitch: (@Sendable (_ registryID: String) -> Bool?)?

    /// The latest permission reading. A `CurrentValueSubject` so `Permissions.shared` can follow it and any
    /// thread can read `.value`. All false until the app delegate has pushed the first reading.
    public static let permissionState = CurrentValueSubject<PortPermissionState, Never>(PortPermissionState())
}
