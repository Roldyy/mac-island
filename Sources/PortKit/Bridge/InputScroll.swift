// SPDX-License-Identifier: GPL-3.0-or-later
// Lane W1A (scroll). The lane owns this file.

/// Binds this lane's ported features. Called once at launch by `PortLanes`, before the registry exists.
/// Nothing is bound yet: fill `bind(into:)` with one `binding.bind(...)` per feature
/// (see `PortFeatureBinding` and `FoundationExampleLane`).
enum InputScrollLane {
    @MainActor static func bind(into binding: PortFeatureBinding) {}
}
