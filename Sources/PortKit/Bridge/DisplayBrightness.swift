// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Lane W2A (display, brightness, keyboard light). The lane owns this file.

import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// Binds this lane's ported features. Called once at launch by `PortLanes`, before the registry exists.
///
/// - `brightness`: sliders for the built-in panel (DisplayServices), Apple displays and external monitors (DDC/CI
///   over IOAVService, gated by a read-only probe; gamma dimming for the rest, never below
///   `BrightnessSupport.softwareDimFloor`), the brightness keys and shortcuts, the keyboard backlight
///   (CoreBrightness) and the per-display power switch. Start is `BrightnessService.syncWithPreferences()`: it
///   arms what the page toggles ask for and nothing else. Stop is the service's `stop()`, which hands the gamma
///   curves and the displays this app switched off back; the registry's kill switch, safe mode, quarantine and a
///   revoked Accessibility grant all end there.
/// - `extraBrightness`: the XDR overlay (public API, a window and a timer, no system state). Start is
///   `syncWithPreferences()`, stop is `stop()`.
///
/// Three pages: `displays` (25) and `extrabrightness` (26) are the pages of the two features; `kbdlight` (63) is
/// a plain page body (it belongs to `brightness` too, which owns one page through the binding).
///
/// Safety nets, in the order they act: the floor under every gamma dim; `stop()` on the kill switch; the
/// `willTerminate` hook below; `recoverAtLaunch` for a run that died dimmed or with a display switched off
/// (called from `PortBridge.recoverAtLaunch`, before the registry starts anything). Nothing here prompts.
enum DisplayBrightnessLane {
    /// What the lane does to the upstream services. The registry tests swap it for a fake.
    struct Runtime {
        var syncBrightness: @MainActor () -> Void
        var stopBrightness: @MainActor () -> Void
        var syncExtraBrightness: @MainActor () -> Void
        var stopExtraBrightness: @MainActor () -> Void
        /// Gamma curves and switched-off displays, back, synchronously. Quit only.
        var restoreBeforeTermination: @MainActor () -> Void

        /// Services are only built once a start reached them: a Mac where the features stay off builds nothing.
        @MainActor private static var brightnessTouched = false
        @MainActor private static var extraTouched = false

        static let live = Runtime(
            syncBrightness: { brightnessTouched = true; BrightnessService.shared.syncWithPreferences() },
            stopBrightness: { if brightnessTouched { BrightnessService.shared.stop() } },
            syncExtraBrightness: { extraTouched = true; ExtraBrightnessService.shared.syncWithPreferences() },
            stopExtraBrightness: { if extraTouched { ExtraBrightnessService.shared.stop() } },
            restoreBeforeTermination: {
                if brightnessTouched { BrightnessService.shared.restoreDisplaysBeforeTermination() }
                if extraTouched { ExtraBrightnessService.shared.stop() }
                DisplayGammaJournal.write(dimmed: false, defaults: PortHost.defaults)
            })
    }

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live)
        installTerminationHook(runtime: .live)
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: Runtime) {
        adoptOldDisplaySwitch(in: PortHost.defaults)
        binding.bind(.brightness,
                     page: PortFeaturePage(pageID: "displays") { AnyView(DisplaysPage()) },
                     start: runtime.syncBrightness, stop: runtime.stopBrightness)
        binding.bind(.extraBrightness,
                     page: PortFeaturePage(pageID: "extrabrightness") { AnyView(ExtraBrightnessPage()) },
                     start: runtime.syncExtraBrightness, stop: runtime.stopExtraBrightness)
        PortBridge.register(pageID: "kbdlight") {
            AnyView(KeyboardLightPage().defaultAppStorage(PortHost.defaults))
        }
    }

    // MARK: Switch adoption

    static let adoptionDoneKey = "migration.display.brightnessAdopted.done"

    /// Mac Island's own Display module kept brightness behind the registry id `display` (shared with auto-quit)
    /// and read `brightnessControlEnabled` as ON when it was never stored. Brightness is now the ported feature
    /// `brightness` with its own switch: once, before the registry reads its switches, a person whose `display`
    /// switch was on and who never chose `brightness` keeps brightness on, with the page toggle as it was.
    /// Written before the registry exists (it reads `shell.enabled.*` at init); the registry stays the only writer
    /// after launch.
    ///
    /// `brightnessControlStored` answers whether the person ever stored `brightnessControlEnabled`. At launch that
    /// is `object(forKey:) != nil`, true because this runs BEFORE `PortBridge.registerDefaults` (the registration
    /// domain is process-wide and would answer `false` for an unstored key); tests inject the answer.
    static func adoptOldDisplaySwitch(
        in defaults: UserDefaults,
        brightnessControlStored: (UserDefaults) -> Bool = { $0.object(forKey: DefaultsKey.brightnessControlEnabled) != nil }
    ) {
        guard !defaults.bool(forKey: adoptionDoneKey) else { return }
        defaults.set(true, forKey: adoptionDoneKey)
        let target = "shell.enabled.brightness"
        guard defaults.object(forKey: target) == nil,
              defaults.object(forKey: "shell.enabled.display") as? Bool == true else { return }
        defaults.set(true, forKey: target)
        if !brightnessControlStored(defaults) {
            defaults.set(true, forKey: DefaultsKey.brightnessControlEnabled)
        }
    }

    // MARK: Quit and launch

    @MainActor private static var terminationObserver: NSObjectProtocol?

    /// The app delegate has no hook for this lane, so it takes its own: when the app quits normally every gamma
    /// curve and every display this app switched off is put back before the process goes. Once.
    @MainActor static func installTerminationHook(runtime: Runtime) {
        guard terminationObserver == nil else { return }
        // No queue: the notification is posted on the main thread and the restore must finish before the process
        // goes, so the block runs inline there.
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { runtime.restoreBeforeTermination() }
        }
    }

    /// Takes the hook out again (tests: it is process-wide).
    @MainActor static func removeTerminationHook() {
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        terminationObserver = nil
    }

    /// Gives back what a run that died left on a screen: a gamma dim (the note of `DisplayGammaJournal`) and the
    /// displays it had switched off (`displaysSwitchedOff`). Each step is entered only when its marker is set, so
    /// a Mac where the display features never ran builds no service and touches no display.
    @MainActor static func recoverAtLaunch(
        defaults: UserDefaults,
        restoreColorSync: () -> Void = { CGDisplayRestoreColorSyncSettings() },
        restoreSwitchedOff: () -> Void = { BrightnessService.shared.restoreDisplaysLeftOff() }
    ) {
        DisplayGammaJournal.recoverAtLaunch(defaults: defaults, restore: restoreColorSync)
        let switchedOff = defaults.array(forKey: DefaultsKey.displaysSwitchedOff) as? [Int] ?? []
        if !switchedOff.isEmpty { restoreSwitchedOff() }
    }
}
