// SPDX-License-Identifier: GPL-3.0-or-later
// Lane W1A (scroll). The lane owns this file.

import SwiftUI

/// Binds this lane's ported features. Called once at launch by `PortLanes`, before the registry exists.
///
/// Four features, two event taps (the upstream design, kept):
/// - `scrollInverter`, `scrollHorizontal` and `linearScroll` share ONE wheel tap, `ScrollInverter`, which stays
///   up while any of the three is wanted. A tail tap on the pointer thread (`PointerTapRunLoop`), plus the
///   HID-stage watcher it asks for (`ScrollWheelHIDStage`, also on the pointer thread).
/// - `smoothScroll` has its own head tap, `SmoothScrollService`, served by the MAIN run loop (its glide engine
///   is main-thread state upstream). The registry's kill switch, safe mode and crash quarantine still remove it.
///
/// Start is the service's `syncWithPreferences()`: it reads the feature's page toggles and arms the tap only
/// when its own gate passes (feature available = the registry let it run, Accessibility, active session). The
/// binding already refuses to call it without Accessibility, and nothing here prompts.
///
/// Stop must not depend on a stored preference, so it is `suspend()` (force-stop). The one shared tap is the
/// exception: stopping one of its three features while another still runs re-syncs instead, so the tap goes
/// down with the last of them. The registry stops all three on the kill switch, safe mode and a permission
/// revoke, and starts them again on the grant.
enum InputScrollLane {
    /// What the lane does to the upstream services. The registry tests swap it for a fake.
    struct Runtime {
        /// Re-reads the preferences and arms or removes the shared wheel tap.
        var syncWheelTap: @MainActor () -> Void
        /// Removes the shared wheel tap whatever the preferences say.
        var suspendWheelTap: @MainActor () -> Void
        var syncSmoothScroll: @MainActor () -> Void
        var suspendSmoothScroll: @MainActor () -> Void

        static let live = Runtime(
            syncWheelTap: { ScrollInverter.shared.syncWithPreferences() },
            suspendWheelTap: { ScrollInverter.shared.suspend() },
            syncSmoothScroll: { SmoothScrollService.shared.syncWithPreferences() },
            suspendSmoothScroll: { SmoothScrollService.shared.suspend() })
    }

    /// The features that share the wheel tap, by upstream id.
    static let wheelTapFeatures = ["scrollInverter", "scrollHorizontal", "linearScroll"]

    /// Upstream feature id -> the Settings page that carries its body (`SettingsPageCatalog` ids).
    static let pages: [(feature: String, pageID: String, parts: Set<MouseSettingsPart>)] = [
        ("scrollInverter", "scrollreverse", [.scrollDirection]),
        ("scrollHorizontal", "hscroll", [.horizontalScroll]),
        ("smoothScroll", "smoothscroll", [.smoothScroll]),
        ("linearScroll", "linearscroll", [.linearScroll]),
    ]

    @MainActor static func bind(into binding: PortFeatureBinding) {
        bind(into: binding, runtime: .live)
    }

    @MainActor static func bind(into binding: PortFeatureBinding, runtime: Runtime) {
        for entry in pages {
            let page = PortFeaturePage(pageID: entry.pageID) { AnyView(MouseSettings(parts: entry.parts)) }
            if wheelTapFeatures.contains(entry.feature) {
                let siblings = wheelTapFeatures.filter { $0 != entry.feature }.compactMap {
                    AppFeature(rawValue: $0)?.registryID
                }
                binding.bind(entry.feature, page: page,
                             start: { runtime.syncWheelTap() },
                             stop: { [weak binding] in
                                 let siblingRuns = siblings.contains { binding?.isStarted($0) == true }
                                 if siblingRuns { runtime.syncWheelTap() } else { runtime.suspendWheelTap() }
                             })
            } else {
                binding.bind(entry.feature, page: page,
                             start: { runtime.syncSmoothScroll() },
                             stop: { runtime.suspendSmoothScroll() })
            }
        }
    }
}
