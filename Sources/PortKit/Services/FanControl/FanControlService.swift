// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import AppKit
import Foundation

/// Mac Island: a shim. It keeps the surface the ported card and the launch recovery read, and forwards every call to
/// `FanControlBackend` (Bridge), which drives Mac Island's own root helper through the Fans model. There is no
/// `SMAppService` registration, no second XPC protocol and no restore-then-unregister here: the helper, its XPC
/// contract and its installation belong to `Sources/Features/Fans` and `Sources/FanShared`.
///
/// Calls arrive on the main thread (SwiftUI, the launch recovery, the quit notification).
final class FanControlService: ObservableObject {
    enum AccessState: Equatable {
        case notRegistered
        case requiresApproval
        case enabled
        case unavailable
    }

    static let shared = FanControlService()

    @Published private(set) var accessState: AccessState = .notRegistered
    @Published private(set) var snapshot: FanControlSnapshot = .empty
    @Published private(set) var error: FanControlErrorCode?
    @Published private(set) var isWorking = false
    /// True while the registry runs the feature (Mac Island's switch, kill switch and safe mode decide).
    @Published private(set) var isRunning = false

    private init() {
        MainActor.assumeIsolated {
            let backend = FanControlBackend.shared
            backend.onChange = { [weak self] state in self?.adopt(state) }
            adopt(backend.state)
        }
    }

    private func adopt(_ state: FanControlBackend.State) {
        if accessState != state.accessState { accessState = state.accessState }
        if snapshot != state.snapshot { snapshot = state.snapshot }
        if error != state.error { error = state.error }
        if isWorking != state.isWorking { isWorking = state.isWorking }
        if isRunning != state.isRunning { isRunning = state.isRunning }
    }

    private static func backend<T: Sendable>(_ body: @MainActor (FanControlBackend) -> T) -> T {
        MainActor.assumeIsolated { body(FanControlBackend.shared) }
    }

    /// Launch recovery: hands back what an earlier run left forced. Entered only when the journal is set.
    static func recoverIfNeeded() {
        backend { $0.recoverAtLaunch() }
    }

    func syncWithPreferences() {
        if AppFeature.fanControl.isAvailable {
            Self.backend { $0.start() }
        } else {
            PortHost.defaults.removeObject(forKey: DefaultsKey.fanControlResumeConfiguration)
            Self.backend { $0.stop() }
        }
    }

    func panelDidAppear() { Self.backend { $0.panelDidAppear() } }

    func panelDidDisappear() { Self.backend { $0.panelDidDisappear() } }

    func refresh() { Self.backend { $0.refresh() } }

    func authorize() { Self.backend { $0.authorize() } }

    func applyConfiguration(_ configuration: FanControlConfiguration) {
        Self.backend { $0.applyConfiguration(configuration) }
    }

    func restoreAutomatic() { Self.backend { $0.restoreAutomatic() } }

    /// The user's own return to System, the one stop a resume must honor.
    func returnToSystem() { Self.backend { $0.returnToSystem() } }

    func resumePreferenceDidChange() { Self.backend { $0.resumePreferenceDidChange() } }

    /// The quit hook of the backend does the same, synchronously; kept for callers that ask by name.
    static func restoreBeforeTerminationIfNeeded() {
        backend { $0.stopNow() }
    }

    // MARK: - Removal of the app

    /// Mac Island's helper is registered and removed by the Fans model, never here: nothing to remember.
    static var hasRegisteredHelperForRemoval: Bool { false }

    static func restoreRegistrationAfterFailedRemoval() -> Bool { true }

    /// Hands every fan back (waits at most half a second) before an uninstall; the registration is not touched.
    static func restoreAndUnregisterForRemoval() -> Bool {
        backend { $0.stopNow() }
        return true
    }
}
