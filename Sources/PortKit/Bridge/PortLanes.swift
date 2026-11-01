// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management

/// Every lane that binds ported features, in one list. `PortBridge.bindLanes()` runs it once at launch, before
/// the `FeatureRegistry` is built, because the registry needs every descriptor at init.
///
/// A new lane adds ONE line here and keeps everything else in its own `Bridge/<Lane>.swift`.
@MainActor
enum PortLanes {
    static let all: [@MainActor (PortFeatureBinding) -> Void] = [
        FoundationExampleLane.bind(into:),
        InputScrollLane.bind(into:),
        InputMouseLane.bind(into:),
        InputKeyboardLane.bind(into:),
        InputShortcutsLane.bind(into:),
        MixerLane.bind(into:),
        DisplayBrightnessLane.bind(into:),
        EnergyLane.bind(into:),
        SwitcherLane.bind(into:),
        WindowLayoutLane.bind(into:),
        DockLane.bind(into:),
        AutoQuitSpacesLane.bind(into:),
        RecorderLane.bind(into:),
        CaptureToolsLane.bind(into:),
        ScreenshotLane.bind(into:),
        MediaToolsLane.bind(into:),
    ]

    static func bindAll(into binding: PortFeatureBinding) {
        for bind in all { bind(binding) }
    }
}
