// SPDX-License-Identifier: GPL-3.0-or-later
// Lane W1D (shortcuts, permissions, cleaning mode). The lane owns this file.

/// Binds this lane's ported features. Called once at launch by `PortLanes`, before the registry exists.
/// Nothing is bound yet: fill `bind(into:)` with one `binding.bind(...)` per feature
/// (see `PortFeatureBinding` and `FoundationExampleLane`).
enum InputShortcutsLane {
    @MainActor static func bind(into binding: PortFeatureBinding) {}
}
