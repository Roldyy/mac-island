// SPDX-License-Identifier: GPL-3.0-or-later
// Lane W1C (keyboard). The lane owns this file.

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The four ported keyboard features, bound through `PortFeatureBinding`.
///
/// | upstream id            | Settings page | start                                   | stop                                     |
/// |------------------------|---------------|-----------------------------------------|------------------------------------------|
/// | `quitWindowProtection` | `quitprotect` | `QuitProtectionService.syncWithPreferences` | `QuitProtectionService.suspend`      |
/// | `keyboardDebounce`     | `debounce`    | `KeyboardDebounceService.syncWithPreferences` | `KeyboardDebounceService.suspend`  |
/// | `superKey`             | `superkey`    | `SuperKeyService.syncWithPreferences`   | `SuperKeyService.suspend` (puts the key back) |
/// | `textSnippets`         | `snippets`    | text expansion + snippet library sync   | both `suspend`                           |
///
/// `PortFeatureBinding` already guarantees that nothing starts while the registry says off or Accessibility is
/// missing, and that nothing ever prompts. Each service also keeps its own page toggle (off by default), so a
/// feature that the registry allows still arms nothing until the user turns it on on its page.
enum InputKeyboardLane {
    /// What the lane calls on the ported services. Tests pass fakes: the live one arms real event taps.
    struct Runtime {
        struct Hooks {
            let start: @MainActor () -> Void
            let stop: @MainActor () -> Void
        }

        var quitProtection: Hooks
        var keyboardDebounce: Hooks
        var superKey: Hooks
        var textSnippets: Hooks

        static let live = Runtime(
            quitProtection: Hooks(start: { QuitProtectionService.shared.syncWithPreferences() },
                                  stop: { QuitProtectionService.shared.suspend() }),
            keyboardDebounce: Hooks(start: { KeyboardDebounceService.shared.syncWithPreferences() },
                                    stop: { KeyboardDebounceService.shared.suspend() }),
            // `suspend` and not `stop`: it takes the hidutil mapping out (the key is never left doing nothing)
            // and also ends the app-exception tracking. Off the main thread, within one 3 s budget, never
            // waited for: a kill switch or safe mode must not freeze the UI behind a hung `hidutil`. What the
            // budget does not finish, the guard child does.
            superKey: Hooks(start: { SuperKeyService.shared.syncWithPreferences() },
                            stop: { SuperKeyService.shared.suspend() }),
            textSnippets: Hooks(start: {
                TextSnippetService.shared.syncWithPreferences()
                SnippetLibraryService.shared.syncWithPreferences()
            }, stop: {
                TextSnippetService.shared.suspend()
                SnippetLibraryService.shared.suspend()
            }))
    }

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live)
        guard !didInstallLaunchSafety else { return }
        didInstallLaunchSafety = true
        recoverLeftoverMapping(defaults: PortHost.defaults) { SuperKeyService.shared.suspend() }
        observeTermination(of: binding) { SuperKeyService.shared.suspendForTermination() }
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: Runtime) {
        binding.bind(.quitWindowProtection,
                     page: PortFeaturePage(pageID: "quitprotect") { AnyView(QuitProtectionSettings()) },
                     start: runtime.quitProtection.start, stop: runtime.quitProtection.stop)
        binding.bind(.keyboardDebounce,
                     page: PortFeaturePage(pageID: "debounce") { AnyView(KeyboardDebounceSettings()) },
                     start: runtime.keyboardDebounce.start, stop: runtime.keyboardDebounce.stop)
        binding.bind(.superKey,
                     page: PortFeaturePage(pageID: "superkey") { AnyView(SuperKeySettings()) },
                     start: runtime.superKey.start, stop: runtime.superKey.stop)
        binding.bind(.textSnippets,
                     page: PortFeaturePage(pageID: "snippets") { AnyView(TextSnippetsSettings()) },
                     start: runtime.textSnippets.start, stop: runtime.textSnippets.stop)
    }

    // MARK: Super key safety

    private nonisolated(unsafe) static var didInstallLaunchSafety = false

    /// A mapping left applied by a run that died before it could clear it (the guard process normally does,
    /// this is the second net): taken out BEFORE the registry starts anything, so the key is never left doing
    /// nothing and the service starts from a clean table if the feature is on. Returns whether it cleared.
    @discardableResult
    static func recoverLeftoverMapping(defaults: UserDefaults, clear: () -> Void) -> Bool {
        guard defaults.bool(forKey: DefaultsKey.superKeyMappingApplied) else { return false }
        clear()
        return true
    }

    /// The app delegate only ends a Finder session at termination, so the lane takes the super key's mapping
    /// out itself when the app quits normally (the guard process covers a crash or a kill). The one place the
    /// main thread waits: at most 2 s (`SuperKeyMappingGuard.StopBudget.terminationTotal`).
    @MainActor @discardableResult
    static func observeTermination(of binding: PortFeatureBinding,
                                   clear: @escaping @MainActor () -> Void) -> NSObjectProtocol {
        // No queue: the notification is posted on the main thread and the clear must finish before the
        // process goes, so the block runs inline there.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: nil) { _ in
            MainActor.assumeIsolated { if binding.isStarted("superKey") { clear() } }
        }
    }
}

/// The last word of every ported keyboard tap, before it looks at a key.
///
/// A tap that holds events (Quit Protection's confirmation, the debounce filter) must hand every event through
/// when its feature is stopped, withdrawn (kill switch, safe mode, quarantine, a revoked permission all make
/// `isAvailable` false) or when macOS Secure Event Input is on, which is the state of a password field: nothing
/// typed there may be held, dropped or rewritten by a ported feature. Reading both is a lock and a flag read,
/// cheap enough for a tap that sees every keystroke.
enum KeyboardTapSafety {
    static func shouldPassThrough(featureAvailable: Bool, secureInputEnabled: Bool) -> Bool {
        !featureAvailable || secureInputEnabled
    }

    static func shouldPassThrough(_ feature: AppFeature) -> Bool {
        shouldPassThrough(featureAvailable: feature.isAvailable, secureInputEnabled: IsSecureEventInputEnabled())
    }
}
